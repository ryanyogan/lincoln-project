defmodule Lincoln.Workers.AutonomousLearningWorker do
  @moduledoc """
  The main autonomous learning loop.

  This is Lincoln's "night shift" - running continuously while a session
  is active, learning from the web, forming beliefs, and potentially
  modifying his own code.

  Each cycle:
  1. Check if session still active
  2. Check budget
  3. Pick a topic to research
  4. Research it (fetch, summarize, extract facts)
  5. Learn from it (form beliefs, create memories)
  6. Queue discovered topics
  7. Maybe reflect and evolve
  8. Schedule next cycle

  "You don't understand. I have lived. I have memories. I am real."
  - Lincoln Six Echo
  """

  use Oban.Worker,
    queue: :autonomy,
    max_attempts: 1,
    unique: [period: 30]

  alias Lincoln.{Agents, Autonomy, Beliefs, Cognition, Memory}
  alias Lincoln.Autonomy.{Evolution, LearningSession, Research, SelfImprovement, TokenBudget}

  require Logger

  # Time between learning cycles (milliseconds)
  @cycle_interval_ms 30_000

  # How often to reflect (every N cycles)
  @reflection_interval 10

  # How often to consider evolution (every N cycles)
  @evolution_interval 20

  # Maximum topic depth (don't go too deep down rabbit holes)
  @max_topic_depth 5

  # ============================================================================
  # Worker Entry Point
  # ============================================================================

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"session_id" => session_id, "cycle" => cycle}}) do
    session = Autonomy.get_session!(session_id)
    agent = Agents.get_agent!(session.agent_id)

    # Check if session should continue
    cond do
      not LearningSession.running?(session) ->
        Logger.info("[Lincoln] Session #{session_id} is no longer running, stopping")
        :ok

      not TokenBudget.has_budget?(session) ->
        Logger.warning("[Lincoln] Budget exhausted, stopping session")
        handle_budget_exhausted(agent, session)
        :ok

      TokenBudget.should_wind_down?(session) ->
        Logger.info("[Lincoln] Budget low, winding down")
        handle_wind_down(agent, session)
        :ok

      true ->
        # Run a learning cycle
        run_learning_cycle(agent, session, cycle)
    end
  end

  # Initial job (no cycle count yet)
  def perform(%Oban.Job{args: %{"session_id" => session_id}}) do
    perform(%Oban.Job{args: %{"session_id" => session_id, "cycle" => 1}})
  end

  # ============================================================================
  # Main Learning Cycle
  # ============================================================================

  defp run_learning_cycle(agent, session, cycle) do
    Logger.info("[Lincoln] Starting learning cycle #{cycle}")

    cycle_start = DateTime.utc_now()

    # Get LLM adapter
    llm = get_llm_adapter()

    # 1. Pick a topic to research
    case pick_topic(agent, session) do
      nil ->
        # No topics - generate some curiosity
        Logger.info("[Lincoln] No topics in queue, generating curiosity")
        generate_curiosity_topics(agent, session, llm)
        schedule_next_cycle(session, cycle)

      topic ->
        # 2. Research the topic
        {:ok, _topic} = Autonomy.start_topic(topic)

        Autonomy.log_activity(
          agent,
          session,
          "topic_start",
          "Starting research on: #{topic.topic}",
          topic_id: topic.id
        )

        case Research.research_topic(agent, session, topic, llm: llm) do
          {:ok, result} ->
            # 3. Learn from the research
            learn_from_research(agent, session, topic, result, llm)

            # 4. Queue discovered topics
            queue_discovered_topics(agent, session, topic, result.related_topics)

            # 5. Mark topic complete
            {:ok, _} =
              Autonomy.complete_topic(
                topic,
                length(result.facts),
                count_beliefs_formed(result.facts),
                length(result.related_topics)
              )

            # Update session counters
            Autonomy.increment_session(session, :topics_explored)
            TokenBudget.record_usage(session, result.tokens_used)

            log_cycle_complete(agent, session, topic, result, cycle_start)

          {:error, :already_fetched} ->
            Logger.debug("[Lincoln] URL already fetched, skipping topic")
            Autonomy.skip_topic(topic, "URL already fetched")

          {:error, reason} ->
            Logger.warning("[Lincoln] Research failed: #{inspect(reason)}")
            Autonomy.fail_topic(topic, inspect(reason))

            Autonomy.log_activity(
              agent,
              session,
              "error",
              "Research failed for #{topic.topic}: #{inspect(reason)}",
              topic_id: topic.id
            )
        end

        # 6. Maybe reflect
        if rem(cycle, @reflection_interval) == 0 do
          maybe_reflect(agent, session, llm)
        end

        # 7. Maybe evolve
        if rem(cycle, @evolution_interval) == 0 do
          maybe_evolve(agent, session, llm)
        end

        # 8. Schedule next cycle
        schedule_next_cycle(session, cycle)
    end

    :ok
  end

  # ============================================================================
  # Topic Selection
  # ============================================================================

  defp pick_topic(agent, session) do
    case Autonomy.get_next_topic(session) do
      nil ->
        nil

      topic ->
        # Check depth limit
        if topic.depth > @max_topic_depth do
          Autonomy.skip_topic(topic, "Max depth exceeded")
          pick_topic(agent, session)
        else
          topic
        end
    end
  end

  defp generate_curiosity_topics(agent, session, llm) do
    # Use existing beliefs and memories to generate curiosity
    beliefs = Beliefs.list_beliefs(agent, limit: 10)
    recent_memories = Memory.list_recent_memories(agent, 24, limit: 10)

    context =
      if beliefs == [] and recent_memories == [] do
        "I am just beginning to learn. I want to understand computers and how they work."
      else
        belief_text = Enum.map_join(beliefs, "\n- ", & &1.statement)
        memory_text = Enum.map_join(recent_memories, "\n- ", & &1.content)

        """
        My current beliefs:
        - #{belief_text}

        Recent memories:
        - #{memory_text}
        """
      end

    prompt = """
    You are Lincoln, an autonomous learning agent. You want to understand
    everything about computers and technology, and also about life and the world.

    Your current knowledge:
    #{context}

    Generate 3-5 topics you're curious about and want to research next.
    Focus on foundational knowledge that builds understanding.

    IMPORTANT: Return ONLY a valid JSON array of strings, nothing else. No markdown, no explanation.
    Format exactly like this: ["Topic One", "Topic Two", "Topic Three"]
    """

    case llm.extract(prompt, %{type: "array"}, max_tokens: 200) do
      {:ok, topics} when is_list(topics) ->
        valid_topics =
          topics
          |> Enum.filter(&is_binary/1)
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        Enum.each(valid_topics, fn topic_name ->
          Autonomy.create_topic(agent, session, %{
            topic: topic_name,
            source: "curiosity",
            priority: 7,
            context: "Self-generated curiosity"
          })
        end)

        if valid_topics != [] do
          Autonomy.log_activity(
            agent,
            session,
            "question",
            "Generated #{length(valid_topics)} curiosity topics",
            details: %{topics: valid_topics}
          )
        end

      {:error, reason} ->
        Logger.warning("[Lincoln] Failed to generate curiosity topics: #{inspect(reason)}")

      _ ->
        Logger.warning("[Lincoln] Failed to generate curiosity topics: unexpected response")
    end
  end

  # ============================================================================
  # Learning from Research
  # ============================================================================

  defp learn_from_research(agent, session, topic, result, _llm) do
    # Form beliefs from extracted facts
    beliefs_formed =
      result.facts
      |> Enum.filter(fn f -> (f["confidence"] || 0.5) >= 0.6 end)
      |> Enum.map(fn fact ->
        case Cognition.form_belief(
               agent,
               fact["fact"],
               "observation",
               evidence: "Learned from #{result.url} while researching #{topic.topic}",
               confidence: fact["confidence"] || 0.7
             ) do
          {:ok, belief} ->
            Autonomy.log_activity(
              agent,
              session,
              "believe",
              "Formed belief: #{String.slice(belief.statement, 0, 80)}...",
              topic_id: topic.id,
              details: %{belief_id: belief.id, confidence: belief.confidence}
            )

            Autonomy.increment_session(session, :beliefs_formed)
            belief

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Create a memory of this research
    {:ok, memory} =
      Memory.record_observation(
        agent,
        "Researched '#{topic.topic}': #{result.summary}",
        importance: 6,
        source_context: %{
          url: result.url,
          title: result.title,
          topic_id: topic.id,
          session_id: session.id
        }
      )

    Autonomy.log_activity(
      agent,
      session,
      "memorize",
      "Created memory of research on #{topic.topic}",
      topic_id: topic.id,
      details: %{memory_id: memory.id}
    )

    Autonomy.increment_session(session, :memories_created)

    {:ok, %{beliefs: beliefs_formed, memory: memory}}
  end

  defp count_beliefs_formed(facts) do
    facts
    |> Enum.filter(fn f -> (f["confidence"] || 0.5) >= 0.6 end)
    |> length()
  end

  # ============================================================================
  # Topic Discovery
  # ============================================================================

  defp queue_discovered_topics(agent, session, parent_topic, related_topics) do
    related_topics
    |> Enum.each(fn topic_text ->
      case Autonomy.queue_discovered_topic(
             agent,
             session,
             topic_text,
             parent_topic,
             max_depth: @max_topic_depth
           ) do
        {:ok, _topic} ->
          Logger.debug("[Lincoln] Queued discovered topic: #{topic_text}")

        {:duplicate, _} ->
          Logger.debug("[Lincoln] Topic already queued: #{topic_text}")

        {:too_deep, _} ->
          Logger.debug("[Lincoln] Topic too deep: #{topic_text}")
      end
    end)
  end

  # ============================================================================
  # Reflection
  # ============================================================================

  defp maybe_reflect(agent, session, llm) do
    unless TokenBudget.should_skip_expensive?(session) do
      Logger.info("[Lincoln] Reflecting on learning progress...")

      Autonomy.log_activity(agent, session, "reflect", "Starting reflection cycle")

      # Get recent learning context
      recent_topics = Autonomy.list_topics(session, status: "completed", limit: 10)
      recent_beliefs = Beliefs.list_beliefs(agent, limit: 10)

      topics_text =
        Enum.map_join(recent_topics, ", ", & &1.topic)

      beliefs_text =
        Enum.map_join(recent_beliefs, "\n", &"- #{&1.statement} (#{round(&1.confidence * 100)}%)")

      prompt = """
      You are Lincoln, reflecting on your autonomous learning session.

      Topics explored: #{topics_text}

      Current beliefs:
      #{beliefs_text}

      Reflect on:
      1. What patterns are you seeing across topics?
      2. What questions do these answers raise?
      3. What should you explore next?
      4. Any insights that synthesize multiple learnings?

      Return a brief reflection (2-3 sentences):
      """

      case llm.complete(prompt, max_tokens: 300) do
        {:ok, reflection} ->
          # Store as reflection memory
          {:ok, _memory} =
            Memory.record_reflection(agent, reflection, importance: 7)

          Autonomy.log_activity(
            agent,
            session,
            "reflect",
            "Reflection: #{String.slice(reflection, 0, 100)}...",
            details: %{full_reflection: reflection}
          )

          TokenBudget.record_usage(session, TokenBudget.estimate_reflection_tokens())

        error ->
          Logger.warning("[Lincoln] Reflection failed: #{inspect(error)}")
      end
    end
  end

  # ============================================================================
  # Evolution (Self-Modification)
  # ============================================================================

  defp maybe_evolve(agent, session, llm) do
    unless TokenBudget.should_skip_expensive?(session) do
      Logger.info("[Lincoln] Considering self-improvement...")

      # First, check for event-driven improvement opportunities from the queue
      # These are high-signal improvements detected from struggles/corrections
      case SelfImprovement.process_next(agent, llm) do
        {:ok, code_change} ->
          Logger.info("[Lincoln] Event-driven improvement applied: #{code_change.file_path}")

          Autonomy.log_activity(
            agent,
            session,
            "evolve",
            "Applied event-driven improvement to #{code_change.file_path}",
            details: %{
              change_id: code_change.id,
              file: code_change.file_path,
              commit: code_change.git_commit
            }
          )

          Autonomy.increment_session(session, :code_changes_made)

        :already_working ->
          Logger.debug("[Lincoln] Already working on an improvement, skipping")

        :queue_empty ->
          # No queued improvements - fall back to reflective evolution
          do_reflective_evolution(agent, session, llm)

        :skipped ->
          # Decided not to proceed with queued improvement
          Logger.debug("[Lincoln] Skipped queued improvement, trying reflective evolution")
          do_reflective_evolution(agent, session, llm)

        {:error, reason} ->
          Logger.warning("[Lincoln] Event-driven improvement failed: #{inspect(reason)}")
          # Still try reflective evolution
          do_reflective_evolution(agent, session, llm)
      end

      TokenBudget.record_usage(session, TokenBudget.estimate_evolution_tokens())
    end
  end

  # Reflective evolution - the original approach where Lincoln analyzes his codebase
  # for potential improvements without being triggered by specific events
  defp do_reflective_evolution(agent, session, llm) do
    # Gather context about recent session
    recent_logs = Autonomy.list_logs(session, limit: 50)

    error_logs =
      recent_logs
      |> Enum.filter(&(&1.activity_type == "error"))
      |> Enum.map_join("\n", & &1.description)

    context = %{
      recent_learnings:
        "Explored #{session.topics_explored} topics, formed #{session.beliefs_formed} beliefs",
      recent_errors: if(error_logs == "", do: "None", else: error_logs)
    }

    case Evolution.reflect_on_codebase(llm, context) do
      {:ok, %{"should_evolve" => true} = suggestion} ->
        Logger.info("[Lincoln] Identified improvement: #{suggestion["description"]}")

        Autonomy.log_activity(
          agent,
          session,
          "evolve",
          "Identified improvement: #{suggestion["description"]}",
          details: suggestion
        )

        # Attempt the evolution
        attempt_evolution(agent, session, suggestion, llm)

      {:ok, %{"should_evolve" => false, "reasoning" => reasoning}} ->
        Logger.debug("[Lincoln] No evolution needed: #{reasoning}")

      error ->
        Logger.warning("[Lincoln] Evolution reflection failed: #{inspect(error)}")
    end
  end

  defp attempt_evolution(agent, session, suggestion, llm) do
    target_file = suggestion["target_file"]
    description = suggestion["description"]
    reasoning = suggestion["reasoning"]

    if Evolution.can_modify?(target_file) do
      case Evolution.propose_change(agent, session, target_file, description, reasoning, llm) do
        {:ok, code_change} ->
          # Apply the change
          case Evolution.apply_change(code_change) do
            {:ok, _} ->
              # Commit it
              case Evolution.commit_change(code_change) do
                {:ok, updated_change} ->
                  Logger.info(
                    "[Lincoln] Self-modification complete: #{updated_change.git_commit}"
                  )

                  Autonomy.log_activity(
                    agent,
                    session,
                    "code_change",
                    "Applied and committed: #{description}",
                    details: %{
                      file: target_file,
                      commit: updated_change.git_commit
                    }
                  )

                  Autonomy.increment_session(session, :code_changes_made)

                error ->
                  Logger.error("[Lincoln] Failed to commit change: #{inspect(error)}")
              end

            error ->
              Logger.error("[Lincoln] Failed to apply change: #{inspect(error)}")
          end

        error ->
          Logger.error("[Lincoln] Failed to propose change: #{inspect(error)}")
      end
    else
      Logger.warning("[Lincoln] Cannot modify protected file: #{target_file}")
    end
  end

  # ============================================================================
  # Session Lifecycle
  # ============================================================================

  defp schedule_next_cycle(session, current_cycle) do
    # Schedule next cycle
    scheduled_at = DateTime.add(DateTime.utc_now(), @cycle_interval_ms, :millisecond)

    %{session_id: session.id, cycle: current_cycle + 1}
    |> new(scheduled_at: scheduled_at)
    |> Oban.insert()

    Logger.debug("[Lincoln] Scheduled cycle #{current_cycle + 1}")
  end

  defp handle_budget_exhausted(agent, session) do
    Autonomy.log_activity(
      agent,
      session,
      "budget_warning",
      "Token budget exhausted, stopping session",
      details: %{tokens_used: session.tokens_used}
    )

    Autonomy.stop_session(session)
  end

  defp handle_wind_down(agent, session) do
    Autonomy.log_activity(
      agent,
      session,
      "session_stop",
      "Winding down due to low budget",
      details: %{
        tokens_used: session.tokens_used,
        remaining: TokenBudget.remaining_tokens(session)
      }
    )

    # Do one final reflection
    llm = get_llm_adapter()
    maybe_reflect(agent, session, llm)

    Autonomy.stop_session(session)
  end

  defp log_cycle_complete(agent, session, topic, result, cycle_start) do
    duration_ms = DateTime.diff(DateTime.utc_now(), cycle_start, :millisecond)

    Autonomy.log_timed_activity(
      agent,
      session,
      "topic_complete",
      "Completed research on: #{topic.topic}",
      cycle_start,
      topic_id: topic.id,
      tokens_used: result.tokens_used,
      details: %{
        facts_extracted: length(result.facts),
        related_topics: length(result.related_topics),
        url: result.url,
        duration_ms: duration_ms
      }
    )
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  defp get_llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the autonomous learning loop for a session.
  """
  def start(session) do
    %{session_id: session.id, cycle: 1}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Starts a new autonomous learning session with seed topics.
  """
  def start_session(agent, seed_topics, opts \\ []) do
    config = %{
      "token_limit" => Keyword.get(opts, :token_limit, 500_000),
      "hourly_limit" => Keyword.get(opts, :hourly_limit, 50_000)
    }

    # Create the session
    {:ok, session} =
      Autonomy.create_session(agent, %{
        seed_topics: seed_topics,
        config: config
      })

    # Queue seed topics
    Autonomy.queue_seed_topics(agent, session, seed_topics)

    # Start the session
    {:ok, session} = Autonomy.start_session(session)

    # Log the start
    Autonomy.log_activity(
      agent,
      session,
      "session_start",
      "Started autonomous learning session",
      details: %{seed_topics: seed_topics, config: config}
    )

    # Start the worker loop
    start(session)

    {:ok, session}
  end
end
