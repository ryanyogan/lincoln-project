defmodule Lincoln.Cognition.ConversationHandler do
  @moduledoc """
  Orchestrates the full cognitive pipeline for conversation.

  This is Lincoln's "brain" that processes each message through:
  1. PERCEIVE - Classify message, detect contradictions
  2. REMEMBER - Retrieve relevant memories and beliefs
  3. REASON - Handle contradictions, build response context
  4. RESPOND - Generate response with cognitive context
  5. LEARN - Store memories, update beliefs (async)

  ## AGI Research Relevance

  This module demonstrates key concepts:
  - Persistent memory across conversations
  - Belief revision from new evidence
  - Source-aware epistemology (training vs observation)
  - Cognitive transparency (what was Lincoln "thinking"?)
  """

  require Logger

  alias Lincoln.{Agents, Beliefs, Memory, Questions, Conversation}
  alias Lincoln.Cognition.{Perception, BeliefRevision}

  defstruct [
    :agent,
    :conversation,
    :user_message,
    :perception,
    :context,
    :contradictions,
    :response,
    :baseline_response,
    :cognitive_metadata
  ]

  @type t :: %__MODULE__{
          agent: map(),
          conversation: map(),
          user_message: String.t(),
          perception: Perception.t(),
          context: map(),
          contradictions: list(),
          response: String.t(),
          baseline_response: String.t() | nil,
          cognitive_metadata: map()
        }

  @doc """
  Processes a user message through the full cognitive pipeline.

  ## Options
  - :include_baseline - Also get raw Claude response for comparison
  - :llm - LLM adapter module (default: from config)
  - :embeddings - Embeddings adapter module (default: from config)

  ## Returns
  {:ok, %CognitiveResult{}} with response and metadata
  """
  def process_message(agent_id, conversation_id, user_message, opts \\ []) do
    include_baseline = Keyword.get(opts, :include_baseline, false)

    # Initialize state
    state = %__MODULE__{
      agent: Agents.get_agent!(agent_id),
      conversation: Conversation.get_conversation!(conversation_id),
      user_message: user_message,
      cognitive_metadata: %{
        memories_retrieved: 0,
        beliefs_consulted: 0,
        beliefs_formed: 0,
        beliefs_revised: 0,
        questions_generated: 0,
        contradiction_detected: false,
        thinking_summary: nil
      }
    }

    # Run the pipeline
    with {:ok, state} <- perceive(state, opts),
         {:ok, state} <- remember(state, opts),
         {:ok, state} <- reason(state, opts),
         {:ok, state} <- respond(state, opts),
         {:ok, state} <- maybe_get_baseline(state, include_baseline, opts),
         :ok <- learn_async(state, opts) do
      {:ok, state}
    else
      {:error, reason} ->
        Logger.error("Cognitive pipeline failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # Pipeline Steps
  # ============================================================================

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

    state =
      state
      |> Map.put(:perception, perception)
      |> Map.put(:contradictions, contradictions)
      |> update_metadata(:contradiction_detected, length(contradictions) > 0)

    {:ok, state}
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
          # Determine correction strength from perception
          strength = state.perception.correction_strength || :moderate

          evidence = %{
            statement: state.user_message,
            source_type: :testimony,
            strength: strength
          }

          decision = BeliefRevision.should_revise?(belief, evidence)

          case decision do
            {:revise, reason} ->
              # Execute the revision
              case BeliefRevision.execute_revision(belief, evidence, decision) do
                {:ok, _new_belief} ->
                  {count + 1,
                   ["Revised belief: #{truncate(belief.statement, 30)} - #{reason}" | notes]}

                _ ->
                  {count, notes}
              end

            {:investigate, reason} ->
              {count, ["Investigating: #{truncate(belief.statement, 30)} - #{reason}" | notes]}

            {:hold, reason} ->
              {count, ["Held belief: #{truncate(belief.statement, 30)} - #{reason}" | notes]}
          end
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

  # Optional: Get baseline Claude response for comparison.
  defp maybe_get_baseline(state, false, _opts), do: {:ok, state}

  defp maybe_get_baseline(state, true, opts) do
    llm = get_llm_adapter(opts)

    case llm.baseline_complete(state.user_message) do
      {:ok, baseline} ->
        {:ok, Map.put(state, :baseline_response, baseline)}

      {:error, _reason} ->
        # Don't fail the whole pipeline if baseline fails
        {:ok, state}
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

    """
    You are Lincoln, a learning agent with persistent memory and beliefs.
    You remember past conversations and can form and revise beliefs based on evidence.

    #{if memories_context != "", do: "## Relevant Memories\n#{memories_context}\n", else: ""}
    #{if beliefs_context != "", do: "## Your Current Beliefs\n#{beliefs_context}\n", else: ""}
    #{contradiction_context}

    ## Guidelines
    - Be natural and conversational
    - Reference past conversations if relevant
    - Express genuine uncertainty when appropriate
    - If you disagree with the user based on strong beliefs, explain politely why
    - If you're updating your understanding, acknowledge it
    - You're curious and enjoy learning new things
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
    memories
    |> Enum.map(fn m -> "- #{m.content}" end)
    |> Enum.join("\n")
  end

  defp format_beliefs(beliefs) when is_list(beliefs) do
    beliefs
    |> Enum.map(fn b ->
      confidence = round(b.confidence * 100)
      "- #{b.statement} (#{confidence}% confident, source: #{b.source_type})"
    end)
    |> Enum.join("\n")
  end

  defp format_contradictions(state) do
    if state.contradictions != [] do
      contradiction_text =
        state.contradictions
        |> Enum.map(fn %{belief: b, contradiction_type: type} ->
          "- Your belief \"#{truncate(b.statement, 50)}\" may be #{type} contradicted"
        end)
        |> Enum.join("\n")

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
