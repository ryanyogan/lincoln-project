defmodule Lincoln.Substrate.InvestigationThought do
  @moduledoc """
  Substrate-native question investigation.

  Picks the oldest open question, gathers context from beliefs and memories,
  calls the LLM for an answer, creates a finding, and forms a belief if
  confidence is high enough. Records an observation memory of the investigation.
  Follow-up questions become research topics for the learning impulse.
  """

  alias Lincoln.{Autonomy, Beliefs, Cognition, Memory, Questions}

  require Logger

  @doc """
  Investigate the most pressing open question.
  Returns {:ok, summary} or {:ok, "No questions to investigate"}.
  """
  def execute(agent) do
    case Questions.list_investigatable_questions(agent, limit: 1) do
      [] ->
        {:ok, "No questions to investigate"}

      [question | _] ->
        investigate(agent, question)
    end
  end

  defp investigate(agent, question) do
    Logger.info("[InvestigationThought] Investigating: #{String.slice(question.question, 0, 60)}")

    context = gather_context(agent, question)

    case generate_answer(question, context) do
      {:ok, answer_data} ->
        process_answer(agent, question, answer_data)

      {:error, reason} ->
        Logger.warning("[InvestigationThought] LLM call failed: #{inspect(reason)}")
        {:error, "Investigation LLM call failed: #{inspect(reason)}"}
    end
  end

  defp gather_context(agent, question) do
    embedding =
      if question.embedding do
        question.embedding
      else
        case embeddings_adapter().embed(question.question, []) do
          {:ok, emb} -> emb
          _ -> nil
        end
      end

    memories =
      if embedding, do: Memory.retrieve_memories(agent, embedding, limit: 5), else: []

    beliefs =
      if embedding, do: Beliefs.find_similar_beliefs(agent, embedding, limit: 5), else: []

    search_results = web_search_results(question.question)

    %{
      relevant_memories: memories,
      relevant_beliefs: beliefs,
      search_results: search_results
    }
  end

  defp web_search_results(query) do
    case search_adapter().search(query, limit: 5) do
      {:ok, results} when is_list(results) ->
        Enum.take(results, 5)

      {:error, reason} ->
        Logger.debug("[InvestigationThought] Search adapter returned error: #{inspect(reason)}")
        []
    end
  rescue
    e ->
      Logger.debug("[InvestigationThought] Search adapter crashed: #{Exception.message(e)}")
      []
  end

  defp generate_answer(question, context) do
    context_text = format_context(context)

    prompt = """
    You are investigating the following question:
    #{question.question}

    Here is relevant information from your memories and beliefs:
    #{context_text}

    Based on this information, provide your best answer.
    Be honest about uncertainty — if you can't answer confidently, say so.

    Return JSON:
    {
      "answer": "Your answer to the question",
      "reasoning": "How you arrived at this answer",
      "confidence": 0.0-1.0,
      "follow_up_questions": ["optional follow-up questions"]
    }
    """

    llm_adapter().extract(prompt, %{type: "object"}, [])
  end

  defp process_answer(agent, question, answer_data) do
    answer = answer_data["answer"] || "No answer produced"
    confidence = answer_data["confidence"] || 0.5
    follow_ups = answer_data["follow_up_questions"] || []

    # Step 1: Create finding — this also resolves the question in a transaction
    case Questions.create_finding(agent, question, %{
           answer: answer,
           source_type: "investigation",
           evidence: answer_data["reasoning"] || "",
           confidence: confidence
         }) do
      {:ok, _finding} ->
        Logger.info(
          "[InvestigationThought] Finding created for question #{String.slice(question.question, 0, 40)}"
        )

        # Step 2: Record observation memory of the investigation
        record_investigation_memory(agent, question, answer, confidence)

        # Step 3: Form belief if confident enough
        if confidence >= 0.7 do
          try do
            Cognition.form_belief(agent, answer, "inference",
              evidence: "From investigating: #{String.slice(question.question, 0, 80)}"
            )
          rescue
            e ->
              Logger.warning(
                "[InvestigationThought] Belief formation failed: #{Exception.message(e)}"
              )
          end
        end

        # Step 4: Queue follow-up questions
        queue_follow_ups(agent, follow_ups)

        summary =
          "Investigated '#{String.slice(question.question, 0, 40)}' → #{String.slice(answer, 0, 60)}"

        Logger.info("[InvestigationThought] #{summary}")
        {:ok, summary}

      {:error, reason} ->
        Logger.error("[InvestigationThought] Failed to create finding: #{inspect(reason)}")

        {:error, "Failed to create finding: #{inspect(reason)}"}

      # Handle the case where create_finding returns just the transaction result
      other ->
        Logger.warning(
          "[InvestigationThought] Unexpected create_finding result: #{inspect(other)}"
        )

        # Still record the observation even if finding creation had unexpected format
        record_investigation_memory(agent, question, answer, confidence)

        summary =
          "Investigated '#{String.slice(question.question, 0, 40)}' → #{String.slice(answer, 0, 60)}"

        {:ok, summary}
    end
  end

  defp record_investigation_memory(agent, question, answer, confidence) do
    content =
      "Investigated question: '#{String.slice(question.question, 0, 120)}' — " <>
        "Answer (confidence #{Float.round(confidence * 100, 0)}%): #{String.slice(answer, 0, 300)}"

    importance = if confidence >= 0.7, do: 7, else: 5

    try do
      Memory.record_observation(agent, content,
        importance: importance,
        context: %{
          question_id: question.id,
          confidence: confidence,
          source: "investigation"
        }
      )
    rescue
      e ->
        Logger.warning("[InvestigationThought] Memory creation failed: #{Exception.message(e)}")
    end
  end

  defp queue_follow_ups(_agent, []), do: :ok

  defp queue_follow_ups(agent, follow_ups) do
    session = Autonomy.get_active_session(agent)
    if session, do: do_queue_follow_ups(agent, session, follow_ups)
  end

  defp do_queue_follow_ups(agent, session, follow_ups) do
    follow_ups
    |> Enum.filter(&(is_binary(&1) and String.length(&1) > 5))
    |> Enum.each(fn q ->
      Autonomy.create_topic(agent, session, %{topic: q, source: "investigation", priority: 5})
    end)
  end

  defp format_context(%{
         relevant_memories: memories,
         relevant_beliefs: beliefs,
         search_results: search_results
       }) do
    parts =
      []
      |> add_section("Relevant memories", memories, fn m -> "- #{m[:content] || m.content}" end)
      |> add_section("Relevant beliefs", beliefs, fn b ->
        "- #{b[:statement] || b.statement} (confidence: #{b[:confidence] || b.confidence})"
      end)
      |> add_section("Web search results", search_results, fn r ->
        "- #{r.title}#{maybe_url(r.url)}#{maybe_snippet(r.snippet)}"
      end)

    if parts == [],
      do: "No relevant context found.",
      else: parts |> Enum.reverse() |> Enum.join("\n\n")
  end

  defp add_section(parts, _label, [], _formatter), do: parts

  defp add_section(parts, label, items, formatter) do
    section = "#{label}:\n" <> Enum.map_join(items, "\n", formatter)
    [section | parts]
  end

  defp maybe_url(nil), do: ""
  defp maybe_url(url), do: " (#{url})"
  defp maybe_snippet(nil), do: ""
  defp maybe_snippet(""), do: ""
  defp maybe_snippet(text), do: " — #{String.slice(text, 0, 200)}"

  defp llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end

  defp embeddings_adapter do
    Application.get_env(:lincoln, :embeddings_adapter, Lincoln.Adapters.Embeddings.PythonService)
  end

  defp search_adapter do
    Application.get_env(:lincoln, :search_adapter, Lincoln.MCP.SearchClient.NoOp)
  end
end
