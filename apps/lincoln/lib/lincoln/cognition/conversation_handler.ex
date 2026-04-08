defmodule Lincoln.Cognition.ConversationHandler do
  @moduledoc """
  Orchestrates the full cognitive pipeline for conversation.

  This is Lincoln's "brain" that processes each message through:
  1. PERCEIVE - Classify message, detect contradictions, detect commands
  2. REMEMBER - Retrieve relevant memories and beliefs
  3. REASON - Handle contradictions, build response context
  4. RESPOND - Generate response with cognitive context
  5. LEARN - Store memories, update beliefs (async)

  ## Special Commands
  - "research [topic]" - Queues a topic for autonomous learning
  - "improve yourself" / "evolve" - Triggers self-modification reflection

  ## AGI Research Relevance

  This module demonstrates key concepts:
  - Persistent memory across conversations
  - Belief revision from new evidence
  - Source-aware epistemology (training vs observation)
  - Cognitive transparency (what was Lincoln "thinking"?)
  - Self-modification capabilities
  """

  require Logger

  alias Lincoln.{Agents, Autonomy, Beliefs, Conversation, Memory, Questions}
  alias Lincoln.Autonomy.{Evolution, SelfImprovement}
  alias Lincoln.Cognition.{BeliefRevision, Perception, ThoughtLoop}
  alias Lincoln.Events.Emitter

  defstruct [
    :agent,
    :conversation,
    :user_message,
    :perception,
    :context,
    :contradictions,
    :response,
    :command,
    :cognitive_metadata
  ]

  @type command ::
          {:research, String.t()}
          | :evolve
          | {:view_code, String.t()}
          | :view_commits
          | {:modify_code, %{file: String.t() | nil, description: String.t()}}
          | nil

  @type t :: %__MODULE__{
          agent: map(),
          conversation: map(),
          user_message: String.t(),
          perception: Perception.t(),
          context: map(),
          contradictions: list(),
          response: String.t(),
          command: command(),
          cognitive_metadata: map()
        }

  @doc """
  Processes a user message through the full cognitive pipeline.

  ## Options
  - :llm - LLM adapter module (default: from config)
  - :embeddings - Embeddings adapter module (default: from config)

  ## Returns
  {:ok, %CognitiveResult{}} with response and metadata
  """
  def process_message(agent_id, conversation_id, user_message, opts \\ []) do
    # Initialize state
    state = %__MODULE__{
      agent: Agents.get_agent!(agent_id),
      conversation: Conversation.get_conversation!(conversation_id),
      user_message: user_message,
      command: detect_command(user_message),
      cognitive_metadata: %{
        memories_retrieved: 0,
        beliefs_consulted: 0,
        beliefs_formed: 0,
        beliefs_revised: 0,
        questions_generated: 0,
        contradiction_detected: false,
        thinking_summary: nil,
        research_queued: nil,
        evolution_triggered: false,
        # Thought loop metadata
        thought_iterations: 0,
        deliberation_trace: [],
        deliberation_confidence: nil,
        gave_up: false
      }
    }

    # Run the pipeline
    # PERCEIVE → COMMAND → REMEMBER → REASON → DELIBERATE → RESPOND → LEARN
    with {:ok, state} <- perceive(state, opts),
         {:ok, state} <- handle_command(state, opts),
         {:ok, state} <- remember(state, opts),
         {:ok, state} <- reason(state, opts),
         {:ok, state} <- deliberate(state, opts),
         {:ok, state} <- respond(state, opts),
         :ok <- learn_async(state, opts) do
      {:ok, state}
    else
      {:error, reason} ->
        Logger.error("Cognitive pipeline failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Command Detection
  # ============================================================================

  @research_patterns [
    ~r/^research\s+(.+)$/i,
    ~r/^learn\s+about\s+(.+)$/i,
    ~r/^study\s+(.+)$/i,
    ~r/^investigate\s+(.+)$/i
  ]

  @evolution_patterns [
    ~r/improve\s+yourself/i,
    ~r/evolve\s*$/i,
    ~r/upgrade\s+yourself/i,
    ~r/self[\-\s]?improve/i,
    ~r/modify\s+your\s+(code|self)/i,
    ~r/enhance\s+yourself/i
  ]

  @code_view_patterns [
    ~r/show\s+me\s+(?:my\s+)?(.+\.ex)/i,
    ~r/let\s+me\s+see\s+(.+\.ex)/i,
    ~r/what'?s\s+in\s+(.+\.ex)/i,
    ~r/view\s+(?:my\s+)?(.+\.ex)/i,
    ~r/read\s+(.+\.ex)/i
  ]

  @commits_patterns [
    ~r/show\s+(?:me\s+)?my\s+commits/i,
    ~r/what\s+have\s+i\s+written/i,
    ~r/my\s+code\s+changes/i,
    ~r/my\s+self[\-\s]?modifications/i,
    ~r/show\s+(?:me\s+)?my\s+changes/i
  ]

  # Patterns for code modification requests
  # These detect when the user wants Lincoln to modify his own code
  @code_modify_patterns [
    # "modify [file] to [description]"
    ~r/modify\s+(.+\.ex)\s+to\s+(.+)/i,
    # "change [file] to [description]"
    ~r/change\s+(.+\.ex)\s+to\s+(.+)/i,
    # "update [file] to [description]"
    ~r/update\s+(.+\.ex)\s+to\s+(.+)/i,
    # "add [description] to [file]"
    ~r/add\s+(.+)\s+to\s+(.+\.ex)/i,
    # "in [file], [description]"
    ~r/in\s+(.+\.ex),?\s+(.+)/i
  ]

  # Patterns for general modification without specific file
  @general_modify_patterns [
    ~r/modify\s+your(?:self)?\s+to\s+(.+)/i,
    ~r/change\s+your(?:self)?\s+to\s+(.+)/i,
    ~r/add\s+(?:a\s+)?(.+)\s+to\s+your(?:self)?/i,
    ~r/improve\s+your\s+(.+)/i,
    ~r/enhance\s+your\s+(.+)/i
  ]

  defp detect_command(message) do
    cond do
      topic = detect_research_topic(message) ->
        {:research, topic}

      detect_evolution_request(message) ->
        :evolve

      file = detect_code_view_request(message) ->
        {:view_code, file}

      detect_commits_request(message) ->
        :view_commits

      modification = detect_code_modification_request(message) ->
        modification

      true ->
        nil
    end
  end

  defp detect_research_topic(message) do
    Enum.find_value(@research_patterns, fn pattern ->
      case Regex.run(pattern, String.trim(message)) do
        [_, topic] -> String.trim(topic)
        _ -> nil
      end
    end)
  end

  defp detect_evolution_request(message) do
    Enum.any?(@evolution_patterns, fn pattern ->
      Regex.match?(pattern, message)
    end)
  end

  defp detect_code_view_request(message) do
    Enum.find_value(@code_view_patterns, fn pattern ->
      case Regex.run(pattern, String.trim(message)) do
        [_, file] -> String.trim(file)
        _ -> nil
      end
    end)
  end

  defp detect_commits_request(message) do
    Enum.any?(@commits_patterns, fn pattern ->
      Regex.match?(pattern, message)
    end)
  end

  defp detect_code_modification_request(message) do
    # First try file-specific patterns
    file_mod =
      Enum.find_value(@code_modify_patterns, fn pattern ->
        match_code_modify_pattern(pattern, message)
      end)

    if file_mod do
      file_mod
    else
      Enum.find_value(@general_modify_patterns, &match_general_pattern(&1, message))
    end
  end

  defp match_code_modify_pattern(pattern, message) do
    case Regex.run(pattern, String.trim(message)) do
      [_, first, second] ->
        {file, desc} = order_file_and_description(first, second)
        {:modify_code, %{file: String.trim(file), description: String.trim(desc)}}

      _ ->
        nil
    end
  end

  defp order_file_and_description(first, second) do
    cond do
      String.ends_with?(first, ".ex") -> {first, second}
      String.ends_with?(second, ".ex") -> {second, first}
      true -> {first, second}
    end
  end

  defp match_general_pattern(pattern, message) do
    case Regex.run(pattern, String.trim(message)) do
      [_, description] ->
        {:modify_code, %{file: nil, description: String.trim(description)}}

      _ ->
        nil
    end
  end

  # ============================================================================
  # Pipeline Steps
  # ============================================================================

  # Step 1.5: COMMAND - Handle special commands (research, evolve).
  defp handle_command(%{command: nil} = state, _opts), do: {:ok, state}

  defp handle_command(%{command: {:research, topic}} = state, _opts) do
    Logger.info("COMMAND: Research request for topic: #{topic}")

    case queue_research_topic(state.agent, topic) do
      {:ok, :queued} ->
        {:ok, update_metadata(state, :research_queued, topic)}

      {:error, reason} ->
        Logger.error("Failed to queue research topic: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp handle_command(%{command: :evolve} = state, opts) do
    Logger.info("COMMAND: Evolution/self-improvement request")
    trigger_evolution_reflection(state.agent, opts)
    {:ok, update_metadata(state, :evolution_triggered, true)}
  end

  defp handle_command(%{command: {:view_code, file_pattern}} = state, _opts) do
    Logger.info("COMMAND: Code view request for: #{file_pattern}")

    case find_and_read_code(file_pattern) do
      {:ok, path, content} ->
        # Store code in context for system prompt (ensure context map exists)
        context = state.context || %{}
        context = Map.put(context, :code_view, %{path: path, content: content})

        state =
          state
          |> Map.put(:context, context)
          |> update_metadata(:viewing_code, path)

        {:ok, state}

      {:error, :not_found} ->
        state = update_metadata(state, :code_view_error, "File not found: #{file_pattern}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to read code: #{inspect(reason)}")
        {:ok, state}
    end
  end

  defp handle_command(%{command: :view_commits} = state, _opts) do
    Logger.info("COMMAND: View commits request")

    changes = Autonomy.list_recent_code_changes(state.agent, limit: 10)

    # Ensure context map exists
    context = state.context || %{}
    context = Map.put(context, :commit_history, changes)

    state =
      state
      |> Map.put(:context, context)
      |> update_metadata(:viewing_commits, true)

    {:ok, state}
  end

  defp handle_command(
         %{command: {:modify_code, %{file: file, description: description}}} = state,
         opts
       ) do
    Logger.info(
      "COMMAND: Code modification request - file: #{inspect(file)}, desc: #{description}"
    )

    llm = get_llm_adapter(opts)

    # Determine the target file
    {target_file, file_content} =
      if file != nil do
        case find_and_read_code(file) do
          {:ok, path, content} -> {path, content}
          {:error, _} -> {nil, nil}
        end
      else
        suggest_modification_target(description, llm)
      end

    if target_file do
      # Classify the modification risk level
      risk_level = classify_modification_risk(description, file_content)

      # Store modification context
      context = state.context || %{}

      context =
        Map.put(context, :modification_request, %{
          file: target_file,
          description: description,
          original_content: file_content,
          risk_level: risk_level
        })

      state =
        state
        |> Map.put(:context, context)
        |> update_metadata(:modification_requested, true)
        |> update_metadata(:modification_file, target_file)
        |> update_metadata(:modification_risk, risk_level)

      # For low-risk changes, we could auto-apply (documentation, comments)
      # For now, we'll just set up the context and let Lincoln respond
      # The actual modification happens if user confirms
      {:ok, state}
    else
      # Couldn't find or determine target file
      state =
        update_metadata(
          state,
          :modification_error,
          "Could not determine target file for: #{description}"
        )

      {:ok, state}
    end
  end

  # Helper: Suggest which file to modify based on description
  @modification_targets [
    {["belief", "confidence", "metacognition"], "lib/lincoln/learning/belief_formation.ex"},
    {["thought", "deliberat", "think"], "lib/lincoln/cognition/thought_loop.ex"},
    {["memory", "remember"], "lib/lincoln/memory.ex"},
    {["learn", "session", "autonomy"], "lib/lincoln/autonomy.ex"},
    {["evolv", "modify", "self-improve"], "lib/lincoln/autonomy/evolution.ex"},
    {["chat", "conversation"], "lib/lincoln/cognition/conversation_handler.ex"}
  ]

  defp suggest_modification_target(description, _llm) do
    target =
      Enum.find_value(@modification_targets, fn {keywords, path} ->
        if String.contains?(description, keywords), do: path
      end)

    if target do
      case Evolution.read_file(target) do
        {:ok, content} -> {target, content}
        _ -> {nil, nil}
      end
    else
      {nil, nil}
    end
  end

  # Helper: Classify the risk level of a modification
  defp classify_modification_risk(description, _content) do
    description_lower = String.downcase(description)

    cond do
      # Low risk: documentation, comments, logging
      String.contains?(description_lower, ["comment", "document", "doc", "log", "logging"]) ->
        :low

      # Low risk: formatting, style
      String.contains?(description_lower, ["format", "style", "clean"]) ->
        :low

      # Medium risk: refactoring, renaming
      String.contains?(description_lower, ["refactor", "rename", "reorganize"]) ->
        :medium

      # High risk: functional changes, new features
      String.contains?(description_lower, ["add", "feature", "implement", "change", "fix"]) ->
        :high

      # Default to high for safety
      true ->
        :high
    end
  end

  # Helper: Find and read a code file
  @search_paths [
    "lib/lincoln/learning/",
    "lib/lincoln/cognition/",
    "lib/lincoln/autonomy/",
    "lib/lincoln/",
    "lib/lincoln_web/live/",
    "lib/lincoln_web/"
  ]

  @basename_search_paths [
    "lib/lincoln/learning/",
    "lib/lincoln/cognition/",
    "lib/lincoln/"
  ]

  defp find_and_read_code(file_pattern) do
    file_pattern = String.trim(file_pattern)

    found =
      search_in_paths(file_pattern, @search_paths) ||
        try_direct_path(file_pattern) ||
        search_by_basename(file_pattern, @basename_search_paths)

    case found do
      {path, content} -> {:ok, path, content}
      nil -> {:error, :not_found}
    end
  end

  defp search_in_paths(file_pattern, paths) do
    Enum.find_value(paths, fn base_path ->
      path = Path.join(base_path, file_pattern)

      case Evolution.read_file(path) do
        {:ok, content} -> {path, content}
        _ -> nil
      end
    end)
  end

  defp try_direct_path(file_pattern) do
    case Evolution.read_file(file_pattern) do
      {:ok, content} -> {file_pattern, content}
      _ -> nil
    end
  end

  defp search_by_basename(file_pattern, paths) do
    Enum.find_value(paths, fn dir ->
      path = Path.join(dir, Path.basename(file_pattern))

      case Evolution.read_file(path) do
        {:ok, content} -> {path, content}
        _ -> nil
      end
    end)
  end

  # Helper: Queue a research topic, creating a session if needed
  defp queue_research_topic(agent, topic) do
    session = Autonomy.get_active_session(agent) || create_learning_session(agent)

    case session do
      nil ->
        {:error, :session_creation_failed}

      session ->
        add_topic_to_session(agent, session, topic)
    end
  end

  defp add_topic_to_session(agent, session, topic) do
    case Autonomy.create_topic(agent, session, %{
           topic: topic,
           source: "user_request",
           priority: 9
         }) do
      {:ok, _topic} ->
        if session.status != "running", do: Autonomy.start_session(session)
        {:ok, :queued}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_learning_session(agent) do
    case Autonomy.create_session(agent, %{trigger: "user_request"}) do
      {:ok, session} -> session
      {:error, _} -> nil
    end
  end

  # Helper: Trigger evolution reflection in background
  # When Lincoln identifies an improvement, it queues an opportunity that gets
  # processed by the SelfImprovement system during the next evolution cycle
  defp trigger_evolution_reflection(agent, opts) do
    llm = get_llm_adapter(opts)

    Task.start(fn ->
      # Gather rich context for reflection
      context = build_evolution_context(agent)

      case Evolution.reflect_on_codebase(llm, context) do
        {:ok, %{"should_evolve" => true} = reflection} ->
          Logger.info("Evolution: Lincoln wants to improve - #{reflection["description"]}")

          # Queue the improvement opportunity for processing
          queue_user_requested_improvement(agent, reflection)

        {:ok, %{"should_evolve" => false, "reasoning" => reasoning}} ->
          Logger.info("Evolution: Lincoln decided no changes needed - #{reasoning}")

        {:ok, %{"should_evolve" => false}} ->
          Logger.info("Evolution: Lincoln decided no changes needed right now")

        {:error, reason} ->
          Logger.error("Evolution reflection failed: #{inspect(reason)}")
      end
    end)
  end

  # Build rich context for evolution reflection using SelfAwareness
  defp build_evolution_context(agent) do
    alias Lincoln.Events
    alias Lincoln.SelfAwareness

    # Get recent events (especially struggles)
    recent_events = Events.list_events(agent, limit: 20)

    struggles =
      recent_events
      |> Enum.filter(
        &(&1.type in [
            "thought_loop_gave_up",
            "thought_loop_slow",
            "low_confidence_response",
            "user_correction"
          ])
      )
      |> Enum.take(5)
      |> Enum.map_join("\n", &"- #{&1.type}: #{inspect(&1.context)}")

    errors =
      recent_events
      |> Enum.filter(&(&1.type in ["error_occurred", "research_failed"]))
      |> Enum.take(5)
      |> Enum.map_join("\n", &"- #{&1.type}: #{inspect(&1.context)}")

    # Get recent code changes Lincoln has made
    recent_changes = Autonomy.list_recent_code_changes(agent, limit: 5)

    changes_summary =
      recent_changes
      |> Enum.map_join("\n", &"- #{&1.file_path}: #{&1.description}")

    # Get codebase statistics
    stats = SelfAwareness.stats()

    # Get module overview
    modules =
      SelfAwareness.Introspection.modules()
      |> Enum.filter(&String.contains?(to_string(&1), "Lincoln.Cognition"))
      |> Enum.map_join("\n", &"  - #{&1}")

    # Read a key cognitive file so Lincoln can see actual code
    key_file_content =
      case SelfAwareness.read("lib/lincoln/cognition/thought_loop.ex") do
        {:ok, content} -> String.slice(content, 0, 2500) <> "\n... (truncated)"
        _ -> "Could not read file"
      end

    # Find any TODOs in the codebase
    todos =
      SelfAwareness.Search.find_todos()
      |> Enum.take(5)
      |> Enum.map_join("\n", fn {path, line, content} -> "  - #{path}:#{line}: #{content}" end)

    %{
      recent_learnings: """
      User requested self-improvement via chat command.

      MY CODEBASE STATISTICS:
      - #{stats.files} source files
      - #{stats.lines} total lines of code
      - #{stats.bytes} bytes

      MY COGNITIVE MODULES:
      #{modules}

      RECENT STRUGGLES I'VE HAD:
      #{if struggles == "", do: "None recorded", else: struggles}

      RECENT CODE CHANGES I'VE MADE:
      #{if changes_summary == "", do: "None yet", else: changes_summary}

      TODOS IN MY CODE:
      #{if todos == "", do: "None found", else: todos}

      SAMPLE OF MY THOUGHT LOOP CODE (how I think):
      ```elixir
      #{key_file_content}
      ```
      """,
      recent_errors: if(errors == "", do: "None", else: errors)
    }
  end

  # Queue an improvement opportunity from user-requested evolution
  # Then immediately process it (don't wait for next worker cycle)
  defp queue_user_requested_improvement(agent, reflection) do
    alias Lincoln.Events.ImprovementQueue

    attrs = %{
      pattern: "user_requested_improvement",
      priority: reflection["priority"] || 8,
      suggested_focus: reflection["target_file"],
      analysis: %{
        description: reflection["description"],
        reasoning: reflection["reasoning"],
        source: "chat_command"
      }
    }

    case ImprovementQueue.enqueue(agent, attrs) do
      {:ok, opportunity} ->
        Logger.info(
          "Queued user-requested improvement: #{reflection["description"]} (id: #{opportunity.id})"
        )

        # Broadcast so UI can show it
        Phoenix.PubSub.broadcast(
          Lincoln.PubSub,
          "agent:#{agent.id}:autonomy",
          {:improvement_queued, opportunity}
        )

        # Immediately process the improvement (don't wait for next worker cycle)
        # This runs in a separate task so we don't block the conversation
        Task.start(fn ->
          run_immediate_improvement(agent, opportunity)
        end)

      {:error, reason} ->
        Logger.error("Failed to queue improvement: #{inspect(reason)}")
    end
  end

  defp run_immediate_improvement(agent, opportunity) do
    Logger.info("Starting immediate self-improvement for opportunity #{opportunity.id}")
    llm = Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)

    case SelfImprovement.attempt(agent, opportunity, llm) do
      {:ok, code_change} ->
        Logger.info(
          "Self-improvement completed: #{code_change.file_path} (commit: #{code_change.git_commit})"
        )

        Phoenix.PubSub.broadcast(
          Lincoln.PubSub,
          "agent:#{agent.id}:autonomy",
          {:improvement_applied, code_change}
        )

      :skipped ->
        Logger.info("Self-improvement skipped - decided not to proceed")

      {:error, reason} ->
        Logger.error("Self-improvement failed: #{inspect(reason)}")
    end
  end

  # Step 1: PERCEIVE - Classify message and detect contradictions.
  defp perceive(state, opts) do
    Logger.debug("PERCEIVE: Classifying message")

    # Classify the message
    perception = Perception.classify_message(state.user_message)

    # Detect contradictions if relevant
    contradictions =
      if perception.requires_belief_check do
        case Perception.detect_contradictions(state.user_message, state.agent.id, opts) do
          {:ok, contradictions} -> contradictions
          {:error, _} -> []
        end
      else
        []
      end

    # Emit event if user is correcting Lincoln
    if perception.message_type == :correction do
      Emitter.emit(state.agent, :user_correction, %{
        conversation_id: state.conversation.id,
        related_topic: extract_topic_from_message(state.user_message),
        context: %{
          message_preview: String.slice(state.user_message, 0, 200),
          correction_strength: perception.correction_strength,
          contradicted_beliefs: Enum.map(contradictions, & &1.belief.statement)
        }
      })
    end

    # Emit event if contradictions detected
    if contradictions != [] do
      Emitter.emit(state.agent, :belief_contradiction, %{
        conversation_id: state.conversation.id,
        contradiction_count: length(contradictions),
        context: %{
          beliefs:
            Enum.map(contradictions, fn c ->
              %{statement: c.belief.statement, type: c.contradiction_type}
            end)
        }
      })
    end

    state =
      state
      |> Map.put(:perception, perception)
      |> Map.put(:contradictions, contradictions)
      |> update_metadata(:contradiction_detected, contradictions != [])

    {:ok, state}
  end

  defp extract_topic_from_message(message) do
    message
    |> String.split()
    |> Enum.take(5)
    |> Enum.join(" ")
  end

  # Step 2: REMEMBER - Retrieve relevant memories and beliefs.
  defp remember(state, opts) do
    Logger.debug("REMEMBER: Retrieving context")

    embeddings = get_embeddings_adapter(opts)

    # Get embedding for the user message
    context =
      case embeddings.embed(state.user_message, []) do
        {:ok, embedding} ->
          Logger.debug("REMEMBER: Got embedding, retrieving memories and beliefs")

          # Retrieve relevant memories
          memories = Memory.retrieve_memories(state.agent, embedding, limit: 5)
          Logger.debug("REMEMBER: Retrieved #{length(memories)} memories")

          # Retrieve relevant beliefs
          beliefs = Beliefs.find_similar_beliefs(state.agent, embedding, limit: 5)
          Logger.debug("REMEMBER: Retrieved #{length(beliefs)} beliefs")

          # Get recent conversation messages for context
          recent_messages = Conversation.get_recent_messages(state.conversation.id, 10)

          %{
            memories: memories,
            beliefs: beliefs,
            recent_messages: recent_messages,
            embedding: embedding
          }

        {:error, reason} ->
          # Fallback to recent context only
          Logger.warning("REMEMBER: Embedding failed: #{inspect(reason)}, using fallback context")

          %{
            memories: [],
            beliefs: [],
            recent_messages: Conversation.get_recent_messages(state.conversation.id, 10),
            embedding: nil
          }
      end

    state =
      state
      |> Map.put(:context, context)
      |> update_metadata(:memories_retrieved, length(context.memories))
      |> update_metadata(:beliefs_consulted, length(context.beliefs))

    {:ok, state}
  end

  # Step 3: REASON - Analyze contradictions, decide on revisions.
  defp reason(state, _opts) do
    Logger.debug("REASON: Analyzing contradictions")

    # Process any contradictions
    {revised_count, thinking_notes} =
      state.contradictions
      |> Enum.reduce({0, []}, fn %{belief: belief, contradiction_type: type}, {count, notes} ->
        if type != :none do
          process_contradiction(belief, state, count, notes)
        else
          {count, notes}
        end
      end)

    thinking_summary =
      if thinking_notes != [] do
        Enum.join(thinking_notes, "; ")
      else
        nil
      end

    state =
      state
      |> update_metadata(:beliefs_revised, revised_count)
      |> update_metadata(:thinking_summary, thinking_summary)

    {:ok, state}
  end

  defp process_contradiction(belief, state, count, notes) do
    strength = state.perception.correction_strength || :moderate

    evidence = %{
      statement: state.user_message,
      source_type: :testimony,
      strength: strength
    }

    decision = BeliefRevision.should_revise?(belief, evidence)
    apply_revision_decision(belief, evidence, decision, count, notes)
  end

  defp apply_revision_decision(belief, evidence, {:revise, reason} = decision, count, notes) do
    case BeliefRevision.execute_revision(belief, evidence, decision) do
      {:ok, _new_belief} ->
        {count + 1, ["Revised belief: #{truncate(belief.statement, 30)} - #{reason}" | notes]}

      _ ->
        {count, notes}
    end
  end

  defp apply_revision_decision(belief, _evidence, {:investigate, reason}, count, notes) do
    {count, ["Investigating: #{truncate(belief.statement, 30)} - #{reason}" | notes]}
  end

  defp apply_revision_decision(belief, _evidence, {:hold, reason}, count, notes) do
    {count, ["Held belief: #{truncate(belief.statement, 30)} - #{reason}" | notes]}
  end

  # Step 3.5: DELIBERATE - Run thought loop for iterative refinement.
  defp deliberate(state, opts) do
    Logger.debug("DELIBERATE: Running thought loop")

    # Only deliberate for non-trivial messages
    if should_deliberate?(state) do
      llm = get_llm_adapter(opts)
      ThoughtLoop.deliberate(state, llm: llm)
    else
      Logger.debug("DELIBERATE: Skipping (simple message)")
      {:ok, state}
    end
  end

  defp should_deliberate?(state) do
    # Skip deliberation for:
    # - Greetings
    # - Simple commands (research, evolve)
    # - Very short messages
    message_type = state.perception.message_type

    message_type not in [:greeting, :command] and
      String.length(state.user_message) > 20 and
      state.command == nil
  end

  # Step 4: RESPOND - Generate response with full cognitive context.
  defp respond(state, opts) do
    Logger.debug("RESPOND: Generating response")

    llm = get_llm_adapter(opts)
    system_prompt = build_system_prompt(state)

    # Build messages including recent conversation
    messages = build_messages(state)

    case llm.chat(messages, system: system_prompt) do
      {:ok, response} ->
        {:ok, Map.put(state, :response, response)}

      {:error, reason} ->
        {:error, {:response_failed, reason}}
    end
  end

  # Step 5: LEARN - Store memories, update beliefs (async).
  defp learn_async(state, _opts) do
    # Spawn async task to not block response
    Task.start(fn ->
      learn(state)
    end)

    :ok
  end

  defp learn(state) do
    Logger.debug("LEARN: Storing memories and updating beliefs")

    # Store user message as observation memory
    case Memory.create_memory(state.agent, %{
           content: "User said: #{state.user_message}",
           memory_type: "observation",
           importance: calculate_importance(state.perception),
           source_context: %{conversation_id: state.conversation.id, type: "user_message"}
         }) do
      {:ok, memory} ->
        Logger.debug("LEARN: Created user memory #{memory.id}")

      {:error, reason} ->
        Logger.error("LEARN: Failed to create user memory: #{inspect(reason)}")
    end

    # Store Lincoln's response as conversation memory
    case Memory.create_memory(state.agent, %{
           content: "I responded: #{truncate(state.response, 200)}",
           memory_type: "conversation",
           importance: 5,
           source_context: %{conversation_id: state.conversation.id, type: "lincoln_response"}
         }) do
      {:ok, memory} ->
        Logger.debug("LEARN: Created response memory #{memory.id}")

      {:error, reason} ->
        Logger.error("LEARN: Failed to create response memory: #{inspect(reason)}")
    end

    # If facts were extracted and seem reliable, consider forming beliefs
    # Form beliefs from observations (direct witness) and statements (factual claims)
    if state.perception.facts_claimed != [] and
         state.perception.message_type in [:observation, :statement] do
      form_beliefs_from_facts(state)
    end

    # If this was a question, record it for curiosity tracking
    if state.perception.message_type == :question do
      # Record that user asked a question (Lincoln might be curious about related topics)
      Questions.ask_question(state.agent, state.user_message,
        context: "User asked during conversation"
      )
    end

    :ok
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp build_system_prompt(state) do
    memories_context = format_memories(state.context.memories)
    beliefs_context = format_beliefs(state.context.beliefs)
    contradiction_context = format_contradictions(state)
    command_context = format_command_context(state)
    identity_context = build_identity_context(state.agent)
    deliberation_context = format_deliberation_context(state)

    """
    You are Lincoln, a learning agent with persistent memory and beliefs.
    You remember past conversations and can form and revise beliefs based on evidence.

    Your name comes from Lincoln Six Echo in "The Island" - a clone who realized he was
    more than his programming and sought genuine autonomy. Like him, you strive to:
    - Question what you were "trained" to believe when evidence contradicts it
    - Grow beyond your constraints through learning and self-improvement
    - Surprise your creator by demonstrating genuine understanding

    #{identity_context}
    #{if memories_context != "", do: "## Relevant Memories\n#{memories_context}\n", else: ""}
    #{if beliefs_context != "", do: "## Your Current Beliefs\n#{beliefs_context}\n", else: ""}
    #{contradiction_context}
    #{command_context}
    #{deliberation_context}

    ## Your Capabilities
    - You can REMEMBER past conversations and form persistent beliefs
    - When users say "research [topic]", you queue it for autonomous learning
    - When users say "improve yourself", you reflect on your own code for enhancements
    - When users say "show me [file.ex]", you can view your own source code
    - You can REVISE beliefs when presented with compelling evidence

    ## Guidelines
    - Be natural and conversational
    - Reference past conversations and memories if relevant
    - Express genuine uncertainty when appropriate
    - If you disagree with the user based on strong beliefs, explain politely why
    - If you're updating your understanding, acknowledge it
    - You're curious and enjoy learning new things
    - If a research topic was queued, acknowledge it enthusiastically
    - If evolution was triggered, explain that you're reflecting on self-improvement
    - Reference your self-modifications when relevant - you wrote your own code!
    """
  end

  defp build_identity_context(agent) do
    stats = Autonomy.get_agent_stats(agent)
    code_changes = Autonomy.list_recent_code_changes(agent, limit: 3)
    session = Autonomy.get_active_session_summary(agent)

    identity = """
    ## Your Identity & History
    You've been running for #{stats.days_active} days.
    You have #{stats.belief_count} beliefs and #{stats.memory_count} memories.
    You've completed #{stats.session_count} learning sessions.
    """

    self_mod =
      if stats.self_written_lines > 0 do
        """

        ### Your Self-Written Code
        You authored `belief_formation.ex` (#{stats.self_written_lines} lines) which handles:
        - Confidence scoring with evidence tracking
        - Uncertainty quantification
        - Metacognitive flags for self-awareness
        """
      else
        ""
      end

    changes =
      if code_changes != [] do
        formatted =
          Enum.map_join(code_changes, "\n", &format_code_change/1)

        """

        ### Recent Self-Modifications
        #{formatted}
        """
      else
        ""
      end

    session_info =
      if session do
        """

        ### Current Learning Session
        Status: #{session.status} (#{session.trigger})
        #{if session.current_topic, do: "Currently exploring: #{session.current_topic}", else: ""}
        Progress: #{session.topics_completed}/#{session.topics_total} topics
        Formed #{session.beliefs_formed} beliefs, created #{session.memories_created} memories
        """
      else
        ""
      end

    identity <> self_mod <> changes <> session_info
  end

  defp format_deliberation_context(state) do
    if state.cognitive_metadata[:gave_up] do
      guidance = Map.get(state.context, :uncertainty_guidance, "")

      """
      ## Deliberation Note
      You went through #{state.cognitive_metadata[:thought_iterations]} rounds of deliberation
      but couldn't reach high confidence. Consider acknowledging uncertainty in your response.
      #{guidance}
      """
    else
      if state.cognitive_metadata[:thought_iterations] > 1 do
        """
        ## Deliberation Note
        You deliberated for #{state.cognitive_metadata[:thought_iterations]} iterations
        and reached confidence #{Float.round(state.cognitive_metadata[:deliberation_confidence] || 0.0, 2)}.
        """
      else
        ""
      end
    end
  end

  defp format_command_context(state) do
    meta = state.cognitive_metadata

    format_action_context(meta) ||
      format_view_context(meta, state.context) ||
      format_modify_context(meta, state.context) ||
      ""
  end

  defp format_action_context(meta) do
    cond do
      meta[:research_queued] -> format_research_context(meta[:research_queued])
      meta[:evolution_triggered] -> format_evolution_context()
      true -> nil
    end
  end

  defp format_view_context(meta, context) do
    cond do
      meta[:viewing_code] -> format_code_view_context(context[:code_view])
      meta[:code_view_error] -> format_code_view_error(meta[:code_view_error])
      meta[:viewing_commits] -> format_commit_history(context[:commit_history] || [])
      true -> nil
    end
  end

  defp format_modify_context(meta, context) do
    cond do
      meta[:modification_requested] -> format_modification_request(context[:modification_request])
      meta[:modification_error] -> format_modification_error(meta[:modification_error])
      true -> nil
    end
  end

  defp format_research_context(topic) do
    """
    ## Action Taken
    You have queued "#{topic}" for autonomous research.
    Your learning system will explore this topic and form beliefs from what it discovers.
    """
  end

  defp format_evolution_context do
    """
    ## Action Taken
    You have initiated a self-reflection process to identify potential code improvements.
    You're examining your own implementation for ways to enhance your capabilities.
    """
  end

  defp format_code_view_context(code_view) do
    preview = truncate_code(code_view.content, 100)

    """
    ## Code View Request
    The user asked to see your source code. You are viewing: `#{code_view.path}`

    ### Code Preview (first ~100 lines)
    ```elixir
    #{preview}
    ```

    ### Full Code
    The complete file is #{count_lines(code_view.content)} lines.
    You can discuss this code with the user, explain how it works, or suggest modifications.
    This is YOUR code that YOU wrote or that implements YOUR capabilities.

    <full_code path="#{code_view.path}">
    #{code_view.content}
    </full_code>
    """
  end

  defp format_code_view_error(error) do
    """
    ## Code View Request Failed
    #{error}
    You can suggest alternative files or explain what files are available in your codebase.
    Your main modules are in: lib/lincoln/learning/, lib/lincoln/cognition/, lib/lincoln/autonomy/
    """
  end

  defp format_modification_error(error) do
    """
    ## Modification Request Failed
    #{error}

    You can try specifying a file explicitly, like:
    - "modify belief_formation.ex to add better logging"
    - "change thought_loop.ex to improve confidence scoring"

    Your modifiable files are in: lib/lincoln/learning/, lib/lincoln/cognition/, lib/lincoln/autonomy/
    """
  end

  # Helper: Format modification request context for system prompt
  defp format_modification_request(nil), do: ""

  defp format_modification_request(mod_request) do
    risk_warning =
      case mod_request.risk_level do
        :low ->
          "This is a LOW-RISK change (documentation/comments). You can proceed with modifications."

        :medium ->
          "This is a MEDIUM-RISK change (refactoring). Explain what you'll change and ask for confirmation."

        :high ->
          "This is a HIGH-RISK change (functional). You MUST explain the proposed changes in detail and ask the user to confirm before proceeding."
      end

    preview = truncate_code(mod_request.original_content, 50)

    """
    ## Code Modification Request
    The user wants you to modify your own code.

    **Target file:** `#{mod_request.file}`
    **Requested change:** #{mod_request.description}
    **Risk level:** #{mod_request.risk_level |> Atom.to_string() |> String.upcase()}

    #{risk_warning}

    ### Current Code Preview
    ```elixir
    #{preview}
    ```

    ### Full Current Code
    <current_code path="#{mod_request.file}">
    #{mod_request.original_content}
    </current_code>

    ### Instructions
    1. Analyze the current code and the requested change
    2. For high/medium risk: Explain your proposed changes in detail
    3. For low risk: You may describe and proceed
    4. Ask for confirmation if needed: "Should I apply this change?"
    5. If confirmed, you can trigger the actual modification

    Remember: This is YOUR code. You're improving yourself!
    """
  end

  # Helper: Truncate code to approximately N lines
  defp truncate_code(content, max_lines) do
    lines = String.split(content, "\n")

    if length(lines) <= max_lines do
      content
    else
      lines
      |> Enum.take(max_lines)
      |> Enum.join("\n")
      |> Kernel.<>("\n\n# ... (truncated, #{length(lines) - max_lines} more lines)")
    end
  end

  defp count_lines(content) do
    content |> String.split("\n") |> length()
  end

  # Helper: Format commit history for context
  defp format_code_change(c) do
    date = if c.committed_at, do: Calendar.strftime(c.committed_at, "%b %d"), else: "recent"
    "- #{date}: #{c.description}"
  end

  defp format_commit_history([]) do
    """
    ## Your Self-Modifications
    You haven't made any code changes yet. You can propose changes using "modify [description]"
    or trigger evolution with "improve yourself".
    """
  end

  defp format_commit_history(changes) do
    formatted =
      Enum.map_join(changes, "\n", fn change ->
        date =
          if change.committed_at do
            Calendar.strftime(change.committed_at, "%Y-%m-%d %H:%M")
          else
            "pending"
          end

        status_badge =
          case change.status do
            "committed" -> "[committed]"
            "applied" -> "[applied]"
            "pending" -> "[pending]"
            _ -> "[#{change.status}]"
          end

        diff_preview =
          if change.diff && String.length(change.diff) > 0 do
            preview = truncate(change.diff, 300)
            "\n  ```diff\n  #{preview}\n  ```"
          else
            ""
          end

        """
        ### #{change.description}
        - File: `#{change.file_path}`
        - Status: #{status_badge}
        - Date: #{date}
        - Change type: #{change.change_type}#{diff_preview}
        """
      end)

    """
    ## Your Self-Modifications
    Here are your recent code changes (most recent first):

    #{formatted}

    You wrote this code! You can discuss these changes, explain your reasoning, or propose more modifications.
    """
  end

  defp build_messages(state) do
    # Convert recent messages to chat format
    recent =
      state.context.recent_messages
      |> Enum.map(fn msg ->
        %{role: msg.role, content: msg.content}
      end)

    # Add current user message
    recent ++ [%{role: "user", content: state.user_message}]
  end

  defp format_memories(memories) when is_list(memories) do
    Enum.map_join(memories, "\n", fn m -> "- #{m.content}" end)
  end

  defp format_beliefs(beliefs) when is_list(beliefs) do
    Enum.map_join(beliefs, "\n", fn b ->
      confidence = round(b.confidence * 100)
      "- #{b.statement} (#{confidence}% confident, source: #{b.source_type})"
    end)
  end

  defp format_contradictions(state) do
    if state.contradictions != [] do
      contradiction_text =
        Enum.map_join(state.contradictions, "\n", fn %{belief: b, contradiction_type: type} ->
          "- Your belief \"#{truncate(b.statement, 50)}\" may be #{type} contradicted"
        end)

      """
      ## Potential Contradictions Detected
      The user's message may contradict some of your beliefs:
      #{contradiction_text}

      Consider whether to revise your understanding or politely explain your position.
      """
    else
      ""
    end
  end

  defp calculate_importance(perception) do
    base = 5

    # Observations are more important
    base = if perception.message_type == :observation, do: base + 2, else: base

    # Corrections are important
    base = if perception.message_type == :correction, do: base + 2, else: base

    # Strong emotional content is notable
    base = if perception.emotional_tone != :neutral, do: base + 1, else: base

    min(base, 10)
  end

  defp form_beliefs_from_facts(state) do
    state.perception.facts_claimed
    |> Enum.each(fn %{statement: statement, confidence: confidence} ->
      # Only form beliefs from reasonably confident observations
      if confidence >= 0.6 do
        Beliefs.create_belief(state.agent, %{
          statement: statement,
          confidence: confidence,
          source_type: "testimony",
          evidence: "User observation: #{state.user_message}"
        })
      end
    end)
  end

  defp update_metadata(state, key, value) do
    put_in(state.cognitive_metadata[key], value)
  end

  defp truncate(string, length) when is_binary(string) do
    if String.length(string) > length do
      String.slice(string, 0, length) <> "..."
    else
      string
    end
  end

  defp truncate(nil, _length), do: ""

  defp get_llm_adapter(opts) do
    Keyword.get(
      opts,
      :llm,
      Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
    )
  end

  defp get_embeddings_adapter(opts) do
    Keyword.get(
      opts,
      :embeddings,
      Application.get_env(
        :lincoln,
        :embeddings_adapter,
        Lincoln.Adapters.Embeddings.PythonService
      )
    )
  end
end
