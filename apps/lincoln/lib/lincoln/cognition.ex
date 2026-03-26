defmodule Lincoln.Cognition do
  @moduledoc """
  The Cognition context - the "thinking" layer.

  This module orchestrates the high-level cognitive processes:
  - Reflection: generating insights from memories
  - Curiosity: generating questions from interests and experiences
  - Belief formation: creating and revising beliefs based on evidence
  - Loop detection: preventing repetitive patterns

  Named after Lincoln Six Echo's cognitive awakening in "The Island".
  """

  alias Lincoln.{Beliefs, Memory, Questions}
  alias Lincoln.Adapters.{LLM, Embeddings}

  # ============================================================================
  # Adapter Resolution (Runtime for Mox compatibility)
  # ============================================================================

  @doc false
  def llm_adapter(opts \\ []) do
    Keyword.get(opts, :llm_adapter) ||
      Application.get_env(:lincoln, :llm_adapter, LLM.Anthropic)
  end

  @doc false
  def embeddings_adapter(opts \\ []) do
    Keyword.get(opts, :embeddings_adapter) ||
      Application.get_env(:lincoln, :embeddings_adapter, Embeddings.PythonService)
  end

  # ============================================================================
  # Reflection
  # ============================================================================

  @doc """
  Performs a reflection cycle for an agent.

  Reflection involves:
  1. Retrieving recent important memories
  2. Using LLM to generate higher-level insights
  3. Storing insights as reflection memories
  4. Potentially forming or revising beliefs
  """
  def reflect(agent, opts \\ []) do
    hours = Keyword.get(opts, :hours, 24)
    llm = llm_adapter(opts)

    with {:ok, memories} <- get_reflection_candidates(agent, hours),
         {:ok, insights} <- generate_insights(memories, llm),
         {:ok, stored} <- store_insights(agent, insights) do
      {:ok, %{insights: stored, memory_count: length(memories)}}
    end
  end

  defp get_reflection_candidates(agent, hours) do
    memories = Memory.list_recent_memories(agent, hours, limit: 50)

    # Filter to memories that haven't been reflected on much
    # and have sufficient importance
    candidates =
      memories
      |> Enum.filter(fn m -> m.importance >= 4 and m.memory_type != "reflection" end)
      |> Enum.take(20)

    {:ok, candidates}
  end

  defp generate_insights(memories, _llm) when length(memories) < 3 do
    # Not enough material for reflection
    {:ok, []}
  end

  defp generate_insights(memories, llm) do
    memory_text =
      memories
      |> Enum.map(fn m -> "- #{m.content}" end)
      |> Enum.join("\n")

    prompt = """
    You are a reflective agent examining your recent experiences.

    Here are your recent memories:
    #{memory_text}

    Based on these experiences, generate 1-3 higher-level insights.
    Each insight should:
    1. Synthesize multiple memories into a broader understanding
    2. Identify patterns or connections
    3. Note anything surprising or worth questioning

    Format your response as a JSON array of objects:
    [
      {
        "insight": "The insight statement",
        "importance": 1-10,
        "related_memories": ["brief reference to related memories"],
        "questions_raised": ["optional questions this raises"]
      }
    ]

    Return ONLY the JSON array.
    """

    case llm.extract(prompt, %{type: "array"}, []) do
      {:ok, insights} when is_list(insights) ->
        {:ok, insights}

      {:ok, _} ->
        {:ok, []}

      {:error, _} = error ->
        error
    end
  end

  defp store_insights(agent, insights) do
    stored =
      Enum.map(insights, fn insight ->
        importance = insight["importance"] || 7

        case Memory.record_reflection(agent, insight["insight"], importance: importance) do
          {:ok, memory} -> memory
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, stored}
  end

  # ============================================================================
  # Curiosity
  # ============================================================================

  @doc """
  Generates questions from the agent's current state.

  Curiosity involves:
  1. Looking at recent experiences and interests
  2. Identifying gaps in knowledge
  3. Generating meaningful questions
  4. Checking for duplicates before storing
  """
  def generate_curiosity(agent, opts \\ []) do
    llm = llm_adapter(opts)
    embeddings = embeddings_adapter(opts)

    with {:ok, context} <- gather_curiosity_context(agent),
         {:ok, questions} <- generate_questions(context, llm),
         {:ok, stored} <- store_questions(agent, questions, embeddings) do
      {:ok, %{questions: stored, context_size: map_size(context)}}
    end
  end

  defp gather_curiosity_context(agent) do
    context = %{
      recent_memories: Memory.list_recent_memories(agent, 24, limit: 10),
      open_questions: Questions.list_open_questions(agent, limit: 5),
      interests: Questions.list_interests(agent),
      beliefs: Beliefs.list_beliefs(agent) |> Enum.take(10)
    }

    {:ok, context}
  end

  defp generate_questions(context, llm) do
    context_text = format_curiosity_context(context)

    prompt = """
    You are a curious agent exploring your understanding of the world.

    Here is your current context:
    #{context_text}

    Generate 1-3 questions you're genuinely curious about.
    Questions should:
    1. Relate to your experiences and interests
    2. Not duplicate existing open questions
    3. Be specific enough to potentially answer
    4. Help fill gaps in your understanding

    Format as JSON:
    [
      {
        "question": "The question text",
        "context": "Why this question is interesting",
        "priority": 1-10
      }
    ]

    Return ONLY the JSON array.
    """

    case llm.extract(prompt, %{type: "array"}, []) do
      {:ok, questions} when is_list(questions) ->
        {:ok, questions}

      {:ok, _} ->
        {:ok, []}

      {:error, _} = error ->
        error
    end
  end

  defp format_curiosity_context(context) do
    parts = []

    parts =
      if length(context.recent_memories) > 0 do
        memories = Enum.map(context.recent_memories, & &1.content) |> Enum.join("\n- ")
        ["Recent memories:\n- #{memories}" | parts]
      else
        parts
      end

    parts =
      if length(context.open_questions) > 0 do
        questions = Enum.map(context.open_questions, & &1.question) |> Enum.join("\n- ")
        ["Open questions:\n- #{questions}" | parts]
      else
        parts
      end

    parts =
      if length(context.interests) > 0 do
        interests = Enum.map(context.interests, & &1.topic) |> Enum.join(", ")
        ["Interests: #{interests}" | parts]
      else
        parts
      end

    parts =
      if length(context.beliefs) > 0 do
        beliefs = Enum.map(context.beliefs, & &1.statement) |> Enum.join("\n- ")
        ["Current beliefs:\n- #{beliefs}" | parts]
      else
        parts
      end

    Enum.reverse(parts) |> Enum.join("\n\n")
  end

  defp store_questions(agent, questions, embeddings) do
    stored =
      Enum.map(questions, fn q ->
        # Generate embedding and semantic hash for deduplication
        {:ok, embedding} = embeddings.embed(q["question"], [])
        semantic_hash = embeddings.semantic_hash(embedding)

        case Questions.ask_question(agent, q["question"],
               context: q["context"],
               priority: q["priority"] || 5,
               embedding: embedding,
               semantic_hash: semantic_hash
             ) do
          {:ok, question} -> question
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:ok, stored}
  end

  # ============================================================================
  # Belief Formation
  # ============================================================================

  @doc """
  Attempts to form a belief from a finding or observation.
  """
  def form_belief(agent, content, source_type, opts \\ []) do
    embeddings = embeddings_adapter(opts)
    evidence = Keyword.get(opts, :evidence)

    # Generate embedding for the potential belief
    {:ok, embedding} = embeddings.embed(content, [])

    # Check for contradictions with existing beliefs
    existing_similar = Beliefs.find_similar_beliefs(agent, embedding, limit: 5, threshold: 0.8)

    cond do
      # Very similar belief already exists - might strengthen it
      Enum.any?(existing_similar, fn b -> b[:similarity] > 0.95 end) ->
        strongest_match = Enum.max_by(existing_similar, & &1[:similarity])
        belief = Beliefs.get_belief!(strongest_match.id)
        Beliefs.strengthen_belief(belief, evidence || content)

      # Somewhat similar beliefs - check for contradiction
      length(existing_similar) > 0 ->
        check_and_resolve_contradictions(
          agent,
          content,
          source_type,
          embedding,
          existing_similar,
          opts
        )

      # No similar beliefs - create new
      true ->
        create_new_belief(agent, content, source_type, embedding, opts)
    end
  end

  defp check_and_resolve_contradictions(
         agent,
         content,
         source_type,
         embedding,
         similar_beliefs,
         opts
       ) do
    llm = llm_adapter(opts)

    similar_text =
      similar_beliefs
      |> Enum.map(fn b -> "- #{b.statement} (confidence: #{b.confidence})" end)
      |> Enum.join("\n")

    prompt = """
    Compare this new potential belief:
    "#{content}"

    With these existing beliefs:
    #{similar_text}

    Determine the relationship:
    1. SUPPORTS - the new belief supports existing beliefs
    2. CONTRADICTS - the new belief contradicts existing beliefs
    3. INDEPENDENT - the beliefs are related but not contradictory
    4. SUPERSEDES - the new belief is a more accurate version

    Return JSON:
    {
      "relationship": "SUPPORTS|CONTRADICTS|INDEPENDENT|SUPERSEDES",
      "reasoning": "Brief explanation",
      "affected_beliefs": ["list of affected belief statements"]
    }
    """

    case llm.extract(prompt, %{type: "object"}, []) do
      {:ok, %{"relationship" => "CONTRADICTS"}} ->
        # For now, create the belief with lower confidence
        # More sophisticated handling would involve AGM contraction
        create_new_belief(
          agent,
          content,
          source_type,
          embedding,
          Keyword.put(opts, :confidence, 0.3)
        )

      {:ok, %{"relationship" => "SUPERSEDES"}} ->
        # Supersede the most similar belief
        if length(similar_beliefs) > 0 do
          old_belief = Beliefs.get_belief!(hd(similar_beliefs).id)

          Beliefs.supersede_belief(
            old_belief,
            %{
              statement: content,
              source_type: source_type,
              embedding: embedding,
              confidence: Keyword.get(opts, :confidence, 0.7)
            },
            "Superseded by more accurate observation"
          )
        else
          create_new_belief(agent, content, source_type, embedding, opts)
        end

      _ ->
        create_new_belief(agent, content, source_type, embedding, opts)
    end
  end

  defp create_new_belief(agent, content, source_type, embedding, opts) do
    Beliefs.create_belief(agent, %{
      statement: content,
      source_type: source_type,
      source_evidence: Keyword.get(opts, :evidence),
      embedding: embedding,
      confidence: Keyword.get(opts, :confidence, 0.6),
      entrenchment: Keyword.get(opts, :entrenchment, 1)
    })
  end

  # ============================================================================
  # Loop Detection
  # ============================================================================

  @doc """
  Checks if an action would create a repetitive loop.
  """
  def would_create_loop?(agent, action_type, content, opts \\ []) do
    embeddings = embeddings_adapter(opts)
    window_hours = Keyword.get(opts, :window_hours, 24)

    # Generate semantic hash for the action
    {:ok, embedding} = embeddings.embed("#{action_type}: #{content}", [])
    semantic_hash = embeddings.semantic_hash(embedding)

    # Check for repetition
    Questions.detect_action_loop(agent, semantic_hash, window_hours)
  end

  @doc """
  Records an action for loop detection.
  """
  def record_action(agent, action_type, content, opts \\ []) do
    embeddings = embeddings_adapter(opts)

    {:ok, embedding} = embeddings.embed("#{action_type}: #{content}", [])
    semantic_hash = embeddings.semantic_hash(embedding)

    Questions.log_action(agent, action_type, %{
      description: content,
      embedding: embedding,
      semantic_hash: semantic_hash,
      triggered_by: Keyword.get(opts, :triggered_by, "user"),
      context: Keyword.get(opts, :context, %{})
    })
  end
end
