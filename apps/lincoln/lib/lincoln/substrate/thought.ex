defmodule Lincoln.Substrate.Thought do
  @moduledoc """
  A single cognitive act — a supervised OTP process with its own lifecycle.

  Each Thought is spawned by ThoughtSupervisor when the Substrate decides
  something is worth thinking about. The Thought owns its execution, records
  its results, broadcasts lifecycle events, and terminates when done.

  This is the architectural claim: thoughts in Lincoln are processes,
  not function calls. They are observable, interruptible, and supervised.
  Python cannot do this.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Cognition, Narratives, PubSubBroadcaster}
  alias Lincoln.Substrate.{CognitiveImpulse, InferenceTier, ThoughtSupervisor, Trajectory}

  defstruct [
    :id,
    :agent_id,
    :belief,
    :attention_score,
    :tier,
    :thought_type,
    :status,
    :result,
    :started_at,
    :completed_at,
    :parent_id,
    :is_narrative,
    :narrative_tick,
    pending_children: %{},
    child_results: []
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts) when is_map(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def child_spec(opts) when is_map(opts) do
    %{
      id: {__MODULE__, Map.get(opts, :id, make_ref())},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary
    }
  end

  @doc "Returns the current state of this Thought process."
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc "Interrupt this thought — it will terminate gracefully after broadcasting the event."
  def interrupt(pid), do: GenServer.cast(pid, :interrupt)

  @doc """
  Spawn a child thought that explores a related belief.
  The child runs under the same ThoughtSupervisor with parent_id set.
  Returns {:ok, child_id} or {:error, reason}.
  """
  def spawn_child(parent_pid, belief, score) do
    GenServer.call(parent_pid, {:spawn_child, belief, score})
  end

  # ============================================================================
  # GenServer callbacks
  # ============================================================================

  @impl true
  def init(%{agent_id: agent_id, belief: belief, attention_score: score} = opts) do
    id = Map.get(opts, :id) || Ecto.UUID.generate()

    agent =
      try do
        Agents.get_agent!(agent_id)
      rescue
        _ -> nil
      end

    tier =
      Map.get(opts, :force_tier) ||
        InferenceTier.select_tier(score, belief: belief, agent: agent)

    state = %__MODULE__{
      id: id,
      agent_id: agent_id,
      belief: belief,
      attention_score: score,
      tier: tier,
      status: :initializing,
      result: nil,
      started_at: DateTime.utc_now(),
      completed_at: nil,
      parent_id: Map.get(opts, :parent_id),
      pending_children: %{},
      child_results: [],
      is_narrative: Map.get(opts, :is_narrative, false),
      narrative_tick: Map.get(opts, :narrative_tick, 0),
      thought_type: Map.get(opts, :thought_type, :elaborate)
    }

    belief_statement = get_statement(belief)

    PubSubBroadcaster.broadcast_thought_event(
      agent_id,
      {:thought_spawned, id, belief_statement, tier, Map.get(opts, :parent_id)}
    )

    Logger.debug("[Thought #{id}] Spawned: #{tier} — #{belief_statement}")

    {:ok, state, {:continue, :execute}}
  end

  @impl true
  def handle_continue(:execute, state) do
    belief_id = state.belief && Map.get(state.belief, :id)

    if is_binary(belief_id) and CognitiveImpulse.impulse?(belief_id) do
      execute_impulse(state, CognitiveImpulse.impulse_type(belief_id))
    else
      execute_belief(state)
    end
  end

  defp execute_impulse(state, impulse_type) do
    Logger.info("[Thought #{state.id}] Executing impulse: #{impulse_type}")
    agent = Agents.get_agent!(state.agent_id)
    _task = Task.async(fn -> run_impulse(agent, impulse_type) end)
    {:noreply, %{state | status: :awaiting_llm}}
  end

  defp execute_belief(%{tier: :local} = state) do
    new_state = execute_local(state)
    finalize(new_state)
    {:stop, :normal, new_state}
  end

  defp execute_belief(%{is_narrative: true} = state) do
    Logger.info("[Thought #{state.id}] Narrative reflection at tick #{state.narrative_tick}")
    _task = Task.async(fn -> run_narrative_llm(state) end)
    {:noreply, %{state | status: :awaiting_llm}}
  end

  defp execute_belief(state) do
    # Don't spawn grandchildren — only top-level thoughts explore
    if state.parent_id do
      _task = Task.async(fn -> run_llm(state.belief, state.tier, state.thought_type) end)
      {:noreply, %{state | status: :awaiting_llm}}
    else
      case find_exploration_candidates(state) do
        [] ->
          _task = Task.async(fn -> run_llm(state.belief, state.tier, state.thought_type) end)
          {:noreply, %{state | status: :awaiting_llm}}

        candidates ->
          Logger.debug(
            "[Thought #{state.id}] Spawning #{length(candidates)} children for exploration"
          )

          new_state = spawn_exploration_children(candidates, state)
          {:noreply, new_state}
      end
    end
  end

  # Child thought completed — track it, synthesize when all done
  @impl true
  def handle_info({:thought_completed, child_id, result}, state)
      when is_map_key(state.pending_children, child_id) do
    pending = Map.put(state.pending_children, child_id, result)
    child_results = [result | state.child_results]
    new_state = %{state | pending_children: pending, child_results: child_results}

    if Enum.all?(pending, fn {_id, r} -> r != nil end) do
      Logger.debug("[Thought #{state.id}] All #{map_size(pending)} children done, synthesizing")
      _task = Task.async(fn -> run_llm_with_children(state.belief, state.tier, child_results) end)
      {:noreply, %{new_state | status: :awaiting_llm}}
    else
      remaining = Enum.count(pending, fn {_id, r} -> r == nil end)
      Logger.debug("[Thought #{state.id}] Waiting for #{remaining} more children")
      {:noreply, new_state}
    end
  end

  # Non-child thought_completed events (from siblings) — ignore
  def handle_info({:thought_completed, _other_id, _result}, state), do: {:noreply, state}

  # Other thought events from the subscription — ignore
  def handle_info({:thought_spawned, _id, _statement, _tier, _parent_id}, state),
    do: {:noreply, state}

  def handle_info({:thought_interrupted, _id, _reason}, state), do: {:noreply, state}
  def handle_info({:thought_failed, _id, _reason}, state), do: {:noreply, state}

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, :skipped} ->
        new_state = %{
          state
          | status: :completed,
            result: "Skipped (budget constraint)",
            completed_at: DateTime.utc_now()
        }

        finalize(new_state)
        {:stop, :normal, new_state}

      {:ok, text} ->
        new_state = %{state | status: :completed, result: text, completed_at: DateTime.utc_now()}

        finalize(new_state)
        {:stop, :normal, new_state}

      {:error, reason} ->
        Logger.warning("[Thought #{state.id}] LLM failed: #{inspect(reason)}")
        new_state = %{state | status: :failed, completed_at: DateTime.utc_now()}

        PubSubBroadcaster.broadcast_thought_event(
          state.agent_id,
          {:thought_failed, state.id, reason}
        )

        {:stop, {:error, reason}, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_cast(:interrupt, state) do
    Logger.debug("[Thought #{state.id}] Interrupted — preempted by higher-priority belief")

    PubSubBroadcaster.broadcast_thought_event(
      state.agent_id,
      {:thought_interrupted, state.id, :preempted}
    )

    {:stop, :interrupted, state}
  end

  @impl true
  def handle_call({:spawn_child, belief, score}, _from, state) do
    case do_spawn_child(belief, score, state) do
      {:ok, child_id, new_state} -> {:reply, {:ok, child_id}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def terminate(:interrupted, state) do
    Logger.info("[Thought #{state.id}] Terminated: interrupted (preempted)")
    :ok
  end

  def terminate(reason, state) do
    Logger.debug("[Thought #{state.id}] Terminating: #{inspect(reason)}")
    :ok
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp run_impulse(agent, :curiosity) do
    case Cognition.generate_curiosity(agent) do
      {:ok, %{questions: questions}} ->
        {:ok, "Curiosity impulse: generated #{length(questions)} questions"}

      {:ok, questions} when is_list(questions) ->
        {:ok, "Curiosity impulse: generated #{length(questions)} questions"}

      {:ok, result} ->
        {:ok, "Curiosity impulse: #{inspect(result)}"}

      {:error, reason} ->
        {:ok, "Curiosity impulse: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :reflection) do
    case Cognition.reflect(agent) do
      {:ok, %{insights: insights}} ->
        {:ok, "Reflection impulse: #{length(insights)} insights"}

      {:ok, insights} when is_list(insights) ->
        {:ok, "Reflection impulse: #{length(insights)} insights"}

      {:ok, result} ->
        {:ok, "Reflection impulse: #{inspect(result)}"}

      {:error, reason} ->
        {:ok, "Reflection impulse: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :self_improve) do
    alias Lincoln.Autonomy.SelfImprovement

    llm = Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)

    case SelfImprovement.process_next(agent, llm) do
      {:ok, code_change} ->
        {:ok, "Self-improvement: modified #{code_change.file_path}"}

      :queue_empty ->
        {:ok, "No improvements pending"}

      :already_working ->
        {:ok, "Already working on an improvement"}

      :skipped ->
        {:ok, "Improvement analyzed but skipped"}

      {:error, reason} ->
        {:ok, "Self-improvement failed: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :investigation) do
    alias Lincoln.Substrate.InvestigationThought

    case InvestigationThought.execute(agent) do
      {:ok, summary} ->
        {:ok, "Investigation impulse: #{summary}"}

      {:error, reason} ->
        {:ok, "Investigation failed: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :learning) do
    alias Lincoln.Substrate.LearningThought

    case LearningThought.execute(agent) do
      {:ok, summary} ->
        {:ok, "Learning impulse: #{summary}"}

      {:error, reason} ->
        {:ok, "Learning impulse failed: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :perception) do
    alias Lincoln.Substrate.PerceptionThought

    case PerceptionThought.execute(agent) do
      {:ok, summary} ->
        {:ok, "Perception impulse: #{summary}"}

      {:error, reason} ->
        {:ok, "Perception impulse failed: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :goal_pursuit) do
    alias Lincoln.Substrate.GoalThought

    case GoalThought.execute(agent) do
      {:ok, summary} ->
        {:ok, "Goal pursuit: #{summary}"}

      {:error, reason} ->
        {:ok, "Goal pursuit failed: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :action) do
    alias Lincoln.Substrate.ActionThought

    case ActionThought.execute(agent) do
      {:ok, summary} ->
        {:ok, "Action: #{summary}"}

      {:error, reason} ->
        {:ok, "Action failed: #{inspect(reason)}"}
    end
  end

  defp run_impulse(agent, :resolve_contradiction) do
    alias Lincoln.Cognition.BeliefRevision

    # Find the most recent unresolved contradiction
    case Lincoln.Beliefs.find_contradictions(agent) do
      [] ->
        {:ok, "No contradictions to resolve"}

      [relationship | _] ->
        belief_a = Lincoln.Beliefs.get_belief!(relationship.source_belief_id)
        belief_b = Lincoln.Beliefs.get_belief!(relationship.target_belief_id)

        evidence_a = %{
          statement: belief_b.statement,
          source_type: belief_b.source_type,
          strength: :moderate
        }

        case BeliefRevision.should_revise?(belief_a, evidence_a) do
          {:revise, reason} ->
            BeliefRevision.execute_revision(belief_a, evidence_a, {:revise, reason})
            {:ok, "Resolved contradiction: revised '#{String.slice(belief_a.statement, 0, 50)}'"}

          {:investigate, _reason} ->
            Lincoln.Beliefs.weaken_belief(belief_a, "Under investigation due to contradiction")
            {:ok, "Investigating contradiction on '#{String.slice(belief_a.statement, 0, 50)}'"}

          {:hold, reason} ->
            {:ok, "Held belief despite contradiction: #{reason}"}
        end
    end
  end

  defp run_impulse(agent, :synthesize_cascade) do
    # Find beliefs with support relationships and synthesize them
    case Lincoln.Beliefs.list_beliefs(agent, status: "active", limit: 10) do
      [] ->
        {:ok, "No beliefs to synthesize"}

      beliefs ->
        # Find beliefs that are part of support clusters
        supported =
          Enum.filter(beliefs, fn b ->
            rels = Lincoln.Beliefs.find_relationships(agent, b.id)
            Enum.any?(rels, &(&1.relationship_type == "supports"))
          end)

        case supported do
          [] ->
            {:ok, "No support clusters found"}

          cluster when length(cluster) >= 2 ->
            statements = Enum.map_join(cluster, "; ", & &1.statement)
            avg_confidence = Enum.sum(Enum.map(cluster, & &1.confidence)) / length(cluster)

            synthesis = "Synthesis: #{statements}"

            Cognition.form_belief(agent, synthesis, "inference",
              evidence: "Synthesized from #{length(cluster)} supporting beliefs",
              confidence: min(1.0, avg_confidence + 0.1),
              entrenchment: 3
            )

            {:ok, "Synthesized #{length(cluster)} beliefs into new inference"}

          _ ->
            {:ok, "Cluster too small to synthesize"}
        end
    end
  end

  defp run_impulse(_agent, type) do
    {:ok, "Unknown impulse type: #{type}"}
  end

  defp execute_local(state) do
    belief_id = state.belief && Map.get(state.belief, :id)

    result =
      if belief_id && is_binary(belief_id) && not CognitiveImpulse.impulse?(belief_id) do
        reason_from_beliefs(state)
      else
        "Local contemplation: #{get_statement(state.belief)}"
      end

    %{state | status: :completed, result: result, completed_at: DateTime.utc_now()}
  end

  defp reason_from_beliefs(state) do
    agent = Agents.get_agent!(state.agent_id)
    belief = Lincoln.Beliefs.get_belief!(state.belief.id)
    relationships = Lincoln.Beliefs.find_relationships(agent, belief.id)

    supports = Enum.filter(relationships, &(&1.relationship_type == "supports"))
    contradictions = Enum.filter(relationships, &(&1.relationship_type == "contradicts"))

    observations =
      analyze_contradictions(belief, contradictions) ++
        analyze_support(supports) ++
        analyze_confidence(belief)

    format_local_reasoning(belief, observations)
  rescue
    _ -> "Local contemplation: #{get_statement(state.belief)}"
  end

  defp analyze_contradictions(belief, [_ | _] = contradictions) do
    count = length(contradictions)

    if belief.confidence > 0.3 do
      Lincoln.Beliefs.weaken_belief(belief, "#{count} contradiction(s) by local reasoning")
    end

    ["contradicted by #{count} belief(s) — confidence reduced"]
  end

  defp analyze_contradictions(_, _), do: []

  defp analyze_support(supports) when length(supports) >= 3 do
    ["well-supported by #{length(supports)} related beliefs"]
  end

  defp analyze_support([]), do: ["isolated — no supporting beliefs"]
  defp analyze_support(_), do: []

  defp analyze_confidence(%{confidence: c, entrenchment: e, revision_count: r}) do
    cond do
      c > 0.8 and e < 3 -> ["confident but untested"]
      c < 0.4 -> ["low confidence — needs evidence"]
      e >= 8 and r < 3 -> ["entrenched but rarely examined"]
      true -> []
    end
  end

  defp format_local_reasoning(belief, []) do
    "Stable: #{String.slice(belief.statement, 0, 60)} (c=#{Float.round(belief.confidence, 2)}, e=#{belief.entrenchment})"
  end

  defp format_local_reasoning(belief, observations) do
    "Local reasoning: #{Enum.join(observations, "; ")} [#{String.slice(belief.statement, 0, 40)}]"
  end

  defp run_llm(belief, tier, thought_type) do
    statement = get_statement(belief)
    related_context = build_related_context(belief)
    system_prompt = thought_type_system_prompt(thought_type)

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: "Belief: #{statement}#{related_context}"}
    ]

    InferenceTier.execute_at_tier(tier, messages, [])
  end

  defp thought_type_system_prompt(:elaborate) do
    "You are a cognitive agent elaborating on a belief. " <>
      "Go deeper — add specific detail, nuances, or implications not yet stated. " <>
      "If it suggests something new, state it as a new claim. Be concise (2-3 sentences)."
  end

  defp thought_type_system_prompt(:critique) do
    "You are a cognitive agent critically examining a belief. " <>
      "Find weaknesses, counterarguments, edge cases, or conditions where it fails. " <>
      "Be honest about limitations. State your critique as a specific claim. Be concise (2-3 sentences)."
  end

  defp thought_type_system_prompt(:connect) do
    "You are a cognitive agent finding connections between ideas. " <>
      "Link this belief to other domains, analogies, or surprising parallels. " <>
      "State the connection as a new claim. Be concise (2-3 sentences)."
  end

  defp thought_type_system_prompt(:abstract) do
    "You are a cognitive agent abstracting from specifics to principles. " <>
      "What higher-level principle does this belief point to? " <>
      "State the abstraction as a new, more general claim. Be concise (2-3 sentences)."
  end

  defp thought_type_system_prompt(:question) do
    "You are a cognitive agent generating questions from a belief. " <>
      "What important questions does this belief raise that aren't yet answered? " <>
      "State 1-2 specific, investigable questions. Be concise."
  end

  defp thought_type_system_prompt(_), do: thought_type_system_prompt(:elaborate)

  defp build_related_context(belief) do
    belief_id = belief && Map.get(belief, :id)

    if belief_id && is_binary(belief_id) do
      try do
        agent = Agents.get_agent!(belief.agent_id)
        relationships = Lincoln.Beliefs.find_relationships(agent, belief_id)

        if relationships != [] do
          related =
            Enum.map_join(relationships, "\n", fn rel ->
              other_id =
                if to_string(rel.source_belief_id) == to_string(belief_id),
                  do: rel.target_belief_id,
                  else: rel.source_belief_id

              other = Lincoln.Beliefs.get_belief!(other_id)

              "- [#{rel.relationship_type}] #{other.statement} (c=#{Float.round(other.confidence, 2)})"
            end)

          "\n\nRelated beliefs in my network:\n#{related}"
        else
          ""
        end
      rescue
        _ -> ""
      end
    else
      ""
    end
  end

  defp run_llm_with_children(belief, tier, child_results) do
    statement = get_statement(belief)

    child_context =
      child_results
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {result, i} -> "#{i}. #{result}" end)

    messages = [
      %{
        role: "system",
        content:
          "You are synthesizing insights from parallel explorations. Be concise (3-4 sentences)."
      },
      %{
        role: "user",
        content: """
        Main belief: #{statement}

        Parallel explorations of related beliefs:
        #{child_context}

        Synthesize these into a coherent reflection on the main belief.
        """
      }
    ]

    InferenceTier.execute_at_tier(tier, messages, [])
  end

  defp run_narrative_llm(state) do
    trajectory_summary =
      try do
        Trajectory.summary(state.agent_id, hours: 1)
      rescue
        _ -> %{total_events: 0, thought_counts: %{completed: 0}}
      end

    completed_thoughts = get_in(trajectory_summary, [:thought_counts, :completed]) || 0

    messages = [
      %{
        role: "system",
        content: """
        You are Lincoln's introspective voice. Write a short autobiographical passage
        (3-5 sentences) in first person describing what you have been thinking about,
        what you have noticed, and how your understanding has shifted recently.
        Be specific about beliefs and topics you have encountered.
        Be honest about uncertainties. Write as a continuous cognitive entity.
        Begin with "I have been..." or "In the last stretch of ticks..."
        """
      },
      %{
        role: "user",
        content: """
        Recent activity (last hour):
        - Substrate events processed: #{trajectory_summary.total_events}
        - Thoughts completed: #{completed_thoughts}
        - Current tick: #{state.narrative_tick}

        Write your reflection now.
        """
      }
    ]

    case InferenceTier.execute_at_tier(:claude, messages, []) do
      {:ok, text} ->
        Task.Supervisor.start_child(Lincoln.TaskSupervisor, fn ->
          try do
            Narratives.create_reflection(state.agent_id, %{
              content: text,
              tick_number: state.narrative_tick,
              period_start_tick: max(0, state.narrative_tick - 200),
              period_end_tick: state.narrative_tick,
              thought_count: completed_thoughts
            })
          rescue
            e ->
              Logger.warning("[Thought] Narrative persist failed: #{Exception.message(e)}")
          end
        end)

        {:ok, text}

      {:error, reason} ->
        Logger.warning("[Thought] Narrative LLM failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp find_exploration_candidates(state) do
    import Ecto.Query

    belief_id =
      Map.get(state.belief, :id) ||
        Map.get(state.belief, "id")

    if is_nil(belief_id) or is_nil(state.agent_id) do
      []
    else
      Lincoln.Beliefs.BeliefRelationship
      |> where(
        [r],
        r.agent_id == ^state.agent_id and
          (r.source_belief_id == ^belief_id or r.target_belief_id == ^belief_id)
      )
      |> preload([:source_belief, :target_belief])
      |> Lincoln.Repo.all()
      |> Enum.flat_map(&active_related_belief(&1, belief_id))
      |> Enum.take(3)
    end
  end

  defp spawn_exploration_children(candidates, state) do
    # Subscribe BEFORE spawning any children to avoid race condition:
    # local-tier children complete instantly in handle_continue and broadcast
    # before the parent would subscribe, causing the parent to miss messages.
    Phoenix.PubSub.subscribe(
      Lincoln.PubSub,
      PubSubBroadcaster.thought_topic(state.agent_id)
    )

    Enum.reduce(candidates, state, fn {belief, score}, acc ->
      case do_spawn_child(belief, score, acc) do
        {:ok, _child_id, new_acc} -> new_acc
        {:error, _reason} -> acc
      end
    end)
  end

  defp do_spawn_child(belief, score, state) do
    child_id = Ecto.UUID.generate()

    child_opts = %{
      id: child_id,
      agent_id: state.agent_id,
      belief: belief,
      attention_score: score,
      parent_id: state.id
    }

    case ThoughtSupervisor.spawn_thought(state.agent_id, child_opts) do
      {:ok, _pid} ->
        pending = Map.put(state.pending_children, child_id, nil)
        new_state = %{state | pending_children: pending, status: :awaiting_children}
        {:ok, child_id, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp active_related_belief(rel, belief_id) do
    related = related_belief_from(rel, belief_id)

    if related && related.status == "active" do
      [{related, 0.2}]
    else
      []
    end
  end

  defp related_belief_from(rel, belief_id) do
    cond do
      to_string(rel.source_belief_id) == to_string(belief_id) -> rel.target_belief
      to_string(rel.target_belief_id) == to_string(belief_id) -> rel.source_belief
      true -> nil
    end
  end

  defp finalize(state) do
    PubSubBroadcaster.broadcast_thought_event(
      state.agent_id,
      {:thought_completed, state.id, state.result}
    )

    if state.result && state.result != "Skipped (budget constraint)" do
      process_thought_result(state.agent_id, state.belief, state.result, state.tier)
    end

    Logger.debug("[Thought #{state.id}] Completed: #{state.tier}")
  end

  defp process_thought_result(agent_id, belief, result, tier) do
    Task.Supervisor.start_child(Lincoln.TaskSupervisor, fn ->
      try do
        agent = Agents.get_agent!(agent_id)
        belief_id = belief && Map.get(belief, :id)

        # Write a "Reflection on X: Y" memory only for substantive belief
        # reflections — skip three kinds of thoughts that already record
        # their work elsewhere or are pure noise:
        #
        #   * local-tier thoughts (cheap, repetitive belief-graph reads)
        #   * narrative thoughts — they have their own narrative_reflections
        #     table; the duplicate memory just floods the trajectory feed
        #   * impulse thoughts — each impulse handler (Investigation,
        #     Perception, Goal, Learning) writes its own purpose-shaped
        #     memory with the right type and importance; the generic
        #     "Reflection on 'I have unprocessed observations': no
        #     extractable claim" memory is duplicate noise.
        should_record_memory? =
          tier != :local and
            is_binary(belief_id) and
            not CognitiveImpulse.impulse?(belief_id)

        if should_record_memory? do
          Lincoln.Memory.create_memory(agent, %{
            content: "Reflection on '#{get_statement(belief)}': #{result}",
            memory_type: "reflection",
            importance: 5
          })
        end

        # Feed back into beliefs — same exclusion: impulses don't have a
        # belief row to revise.
        if belief_id && is_binary(belief_id) && not CognitiveImpulse.impulse?(belief_id) do
          feed_back_to_beliefs(agent, belief, result, tier)
        end
      rescue
        e -> Logger.warning("[Thought] Result processing failed: #{Exception.message(e)}")
      end
    end)
  end

  defp feed_back_to_beliefs(_agent, _belief, _result, :local) do
    # Local-tier thoughts do NOT entrench beliefs.
    # Only LLM-confirmed reflections should increase entrenchment.
    # Local reasoning checks the graph and reports status — that's it.
    :ok
  end

  defp feed_back_to_beliefs(agent, belief, result, _tier) do
    # LLM-tier: evaluate whether reflection reinforces or challenges
    case Cognition.evaluate_reflection(result) do
      :reinforce ->
        live_belief = Lincoln.Beliefs.get_belief!(belief.id)
        Lincoln.Beliefs.strengthen_belief(live_belief, "Reinforced by reflection")

        # LLM reinforcement can entrench up to 6 — only user input should go higher
        if live_belief.entrenchment < 6 do
          Lincoln.Beliefs.entrench_belief(live_belief)
        end

      :challenge ->
        live_belief = Lincoln.Beliefs.get_belief!(belief.id)
        Lincoln.Beliefs.weaken_belief(live_belief, "Challenged by reflection")

      {:extend, insight} ->
        # Rate-limit: only form new belief if we haven't created too many recently
        recent_inferences =
          Lincoln.Beliefs.list_beliefs(agent, status: "active")
          |> Enum.count(fn b ->
            b.source_type == "inference" and
              b.inserted_at != nil and
              DateTime.diff(DateTime.utc_now(), b.inserted_at, :second) < 300
          end)

        if recent_inferences < 5 do
          Cognition.form_belief(agent, insight, "inference",
            evidence: "Extended from: #{get_statement(belief)}",
            confidence: 0.6,
            parent_belief_ids: [belief.id]
          )
        end

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp get_statement(belief) when is_map(belief) do
    Map.get(belief, :statement) || Map.get(belief, "statement") || inspect(belief)
  end
end
