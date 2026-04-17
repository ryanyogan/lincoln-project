defmodule Lincoln.Substrate.InvestigationThought do
  @moduledoc """
  Substrate-native question investigation — extracted from InvestigationWorker.

  Picks the oldest open question, gathers context from beliefs and memories,
  calls the LLM for an answer, creates a finding, and forms a belief if
  confidence is high enough. Follow-up questions become research topics
  for the learning impulse.
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
        {:ok, "Investigation failed: #{inspect(reason)}"}
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

    %{relevant_memories: memories, relevant_beliefs: beliefs}
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

    # Create finding
    Questions.create_finding(agent, question, %{
      answer: answer,
      source_type: "investigation",
      evidence: answer_data["reasoning"] || "",
      confidence: confidence
    })

    # Form belief if confident enough
    if confidence >= 0.7 do
      Cognition.form_belief(agent, answer, "inference",
        evidence: "From investigating: #{String.slice(question.question, 0, 80)}"
      )
    end

    # Queue follow-up questions as research topics
    queue_follow_ups(agent, follow_ups)

    # Resolve the question
    Questions.resolve_question(question, %Lincoln.Questions.Finding{
      answer: answer,
      confidence: confidence
    })

    summary =
      "Investigated '#{String.slice(question.question, 0, 40)}' → #{String.slice(answer, 0, 60)}"

    Logger.info("[InvestigationThought] #{summary}")
    {:ok, summary}
  rescue
    e ->
      Logger.warning("[InvestigationThought] Processing failed: #{Exception.message(e)}")
      {:ok, "Investigation completed but processing failed"}
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

  defp format_context(%{relevant_memories: memories, relevant_beliefs: beliefs}) do
    parts = []

    parts =
      if memories != [] do
        mem_text = Enum.map_join(memories, "\n", fn m -> "- #{m[:content] || m.content}" end)
        ["Relevant memories:\n#{mem_text}" | parts]
      else
        parts
      end

    parts =
      if beliefs != [] do
        bel_text =
          Enum.map_join(beliefs, "\n", fn b ->
            "- #{b[:statement] || b.statement} (confidence: #{b[:confidence] || b.confidence})"
          end)

        ["Relevant beliefs:\n#{bel_text}" | parts]
      else
        parts
      end

    if parts == [],
      do: "No relevant context found.",
      else: parts |> Enum.reverse() |> Enum.join("\n\n")
  end

  defp llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, Lincoln.Adapters.LLM.Anthropic)
  end

  defp embeddings_adapter do
    Application.get_env(:lincoln, :embeddings_adapter, Lincoln.Adapters.Embeddings.PythonService)
  end
end
