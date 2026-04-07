defmodule Lincoln.Workers.InvestigationWorker do
  @moduledoc """
  Oban worker for investigating open questions.

  This worker attempts to answer questions by:
  1. Gathering relevant context (memories, beliefs)
  2. Using the LLM to reason about the question
  3. Creating findings and potentially new beliefs
  """
  use Oban.Worker,
    queue: :investigation,
    max_attempts: 3

  alias Lincoln.Adapters.{Embeddings, LLM}
  alias Lincoln.{Agents, Beliefs, Cognition, Memory, Questions}

  require Logger

  # Use runtime adapter resolution for Mox compatibility
  defp llm_adapter do
    Application.get_env(:lincoln, :llm_adapter, LLM.Anthropic)
  end

  defp embeddings_adapter do
    Application.get_env(:lincoln, :embeddings_adapter, Embeddings.PythonService)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"question_id" => question_id}}) do
    question = Questions.get_question!(question_id)
    agent = Agents.get_agent!(question.agent_id)

    investigate_question(agent, question)
  end

  def perform(%Oban.Job{args: %{"agent_id" => agent_id}}) do
    agent = Agents.get_agent!(agent_id)

    # Get questions ready for investigation
    questions = Questions.list_investigatable_questions(agent, limit: 3)

    Enum.each(questions, fn q ->
      investigate_question(agent, q)
    end)

    :ok
  end

  defp investigate_question(agent, question) do
    Logger.info("Investigating question for #{agent.name}: #{question.question}")

    # Check for loop
    if Cognition.would_create_loop?(agent, "investigate", question.question) do
      Logger.warning("Loop detected for question: #{question.question}")
      Questions.abandon_question(question)
      :ok
    else
      do_investigate(agent, question)
    end
  end

  defp do_investigate(agent, question) do
    # Gather context
    {:ok, embedding} =
      if question.embedding do
        {:ok, question.embedding}
      else
        embeddings_adapter().embed(question.question)
      end

    context = %{
      relevant_memories: Memory.retrieve_memories(agent, embedding, limit: 5),
      relevant_beliefs: Beliefs.find_similar_beliefs(agent, embedding, limit: 5)
    }

    # Generate answer
    case generate_answer(question, context) do
      {:ok, answer_data} ->
        # Create finding
        {:ok, finding} =
          Questions.create_finding(agent, question, %{
            answer: answer_data["answer"],
            source_type: "investigation",
            evidence: answer_data["reasoning"],
            confidence: answer_data["confidence"] || 0.6
          })

        # Potentially form a belief from the finding
        if (answer_data["confidence"] || 0.6) >= 0.7 do
          Cognition.form_belief(
            agent,
            answer_data["answer"],
            "inference",
            evidence: "From investigating: #{question.question}"
          )
        end

        # Record the action
        Cognition.record_action(agent, "investigate", question.question, triggered_by: "schedule")

        Logger.info("Investigation complete for: #{question.question}")
        {:ok, finding}

      {:error, reason} ->
        Logger.error("Investigation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_answer(question, context) do
    context_text = format_investigation_context(context)

    prompt = """
    You are investigating the following question:
    #{question.question}

    Context from your question: #{question.context || "None provided"}

    Here is relevant information from your memories and beliefs:
    #{context_text}

    Based on this information, provide your best answer.
    Be honest about uncertainty - if you can't answer confidently, say so.

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

  defp format_investigation_context(context) do
    parts = []

    parts =
      if context.relevant_memories != [] do
        memories =
          Enum.map_join(context.relevant_memories, "\n", fn m ->
            "- #{m[:content] || m.content}"
          end)

        ["Relevant memories:\n#{memories}" | parts]
      else
        parts
      end

    parts =
      if context.relevant_beliefs != [] do
        beliefs =
          Enum.map_join(context.relevant_beliefs, "\n", fn b ->
            statement = b[:statement] || b.statement
            confidence = b[:confidence] || b.confidence
            "- #{statement} (confidence: #{confidence})"
          end)

        ["Relevant beliefs:\n#{beliefs}" | parts]
      else
        parts
      end

    if parts == [] do
      "No directly relevant context found."
    else
      Enum.reverse(parts) |> Enum.join("\n\n")
    end
  end

  @doc """
  Enqueues investigation for a specific question.
  """
  def enqueue_question(question_id) do
    %{question_id: question_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues investigation for all ready questions for an agent.
  """
  def enqueue_for_agent(agent_id) do
    %{agent_id: agent_id}
    |> new()
    |> Oban.insert()
  end
end
