defmodule LincolnWeb.API.AgentController do
  @moduledoc """
  API controller for external agent interaction.

  Provides JSON API endpoints for:
  - Recording observations and experiences
  - Asking questions and receiving findings
  - Querying beliefs and memories
  - Getting agent status
  """
  use LincolnWeb, :controller

  alias Lincoln.{Agents, Beliefs, Memory, Questions}

  action_fallback(LincolnWeb.API.FallbackController)

  # ============================================================================
  # Agent Status
  # ============================================================================

  @doc """
  GET /api/agent

  Returns the current agent's status and stats.
  """
  def show(conn, _params) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    json(conn, %{
      id: agent.id,
      name: agent.name,
      description: agent.description,
      status: agent.status,
      stats: %{
        beliefs_count: agent.beliefs_count,
        memories_count: agent.memories_count,
        questions_asked_count: agent.questions_asked_count
      },
      created_at: agent.inserted_at,
      updated_at: agent.updated_at
    })
  end

  # ============================================================================
  # Beliefs
  # ============================================================================

  @doc """
  GET /api/beliefs

  Returns the agent's beliefs with optional filtering.
  """
  def list_beliefs(conn, params) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    opts =
      []
      |> maybe_add_opt(:min_confidence, params["min_confidence"], &parse_float/1)
      |> maybe_add_opt(:max_confidence, params["max_confidence"], &parse_float/1)
      |> maybe_add_opt(:status, params["status"])
      |> maybe_add_opt(:limit, params["limit"], &parse_int/1)

    beliefs = Beliefs.list_beliefs(agent, opts)

    json(conn, %{
      beliefs: Enum.map(beliefs, &serialize_belief/1),
      count: length(beliefs)
    })
  end

  @doc """
  POST /api/beliefs

  Creates a new belief.
  """
  def create_belief(conn, %{"belief" => belief_params}) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    with {:ok, belief} <- Beliefs.create_belief(agent, belief_params) do
      conn
      |> put_status(:created)
      |> json(%{belief: serialize_belief(belief)})
    end
  end

  @doc """
  GET /api/beliefs/:id

  Returns a specific belief.
  """
  def get_belief(conn, %{"id" => id}) do
    belief = Beliefs.get_belief!(id)
    json(conn, %{belief: serialize_belief(belief)})
  end

  # ============================================================================
  # Questions
  # ============================================================================

  @doc """
  GET /api/questions

  Returns the agent's questions with optional filtering.
  """
  def list_questions(conn, params) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    questions =
      case params["status"] do
        "open" ->
          Questions.list_open_questions(agent, limit: parse_int(params["limit"]) || 50)

        status when is_binary(status) ->
          Questions.list_questions(agent, status: status, limit: parse_int(params["limit"]) || 50)

        _ ->
          Questions.list_questions(agent, limit: parse_int(params["limit"]) || 50)
      end

    json(conn, %{
      questions: Enum.map(questions, &serialize_question/1),
      count: length(questions)
    })
  end

  @doc """
  POST /api/questions

  Asks a new question.
  """
  def ask_question(conn, %{"question" => question_text} = params) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    opts =
      []
      |> maybe_add_opt(:context, params["context"])
      |> maybe_add_opt(:priority, params["priority"], &parse_int/1)
      |> maybe_add_opt(:semantic_hash, params["semantic_hash"])

    with {:ok, question} <- Questions.ask_question(agent, question_text, opts) do
      conn
      |> put_status(:created)
      |> json(%{question: serialize_question(question)})
    end
  end

  @doc """
  GET /api/questions/:id

  Returns a specific question with its findings.
  """
  def get_question(conn, %{"id" => id}) do
    question = Questions.get_question!(id)
    findings = Questions.list_findings_for_question(question)

    json(conn, %{
      question: serialize_question(question),
      findings: Enum.map(findings, &serialize_finding/1)
    })
  end

  @doc """
  POST /api/questions/:id/findings

  Creates a finding that answers a question.
  """
  def create_finding(conn, %{"id" => question_id, "finding" => finding_params}) do
    {:ok, agent} = Agents.get_or_create_default_agent()
    question = Questions.get_question!(question_id)

    with {:ok, finding} <- Questions.create_finding(agent, question, finding_params) do
      conn
      |> put_status(:created)
      |> json(%{finding: serialize_finding(finding)})
    end
  end

  # ============================================================================
  # Memories
  # ============================================================================

  @doc """
  GET /api/memories

  Returns the agent's memories with optional filtering.
  """
  def list_memories(conn, params) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    opts =
      []
      |> maybe_add_opt(:memory_type, params["type"])
      |> maybe_add_opt(:min_importance, params["min_importance"], &parse_int/1)
      |> maybe_add_opt(:limit, params["limit"], &parse_int/1)

    memories = Memory.list_memories(agent, opts)

    json(conn, %{
      memories: Enum.map(memories, &serialize_memory/1),
      count: length(memories)
    })
  end

  @doc """
  POST /api/memories

  Creates a new memory.
  """
  def create_memory(conn, %{"memory" => memory_params}) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    with {:ok, memory} <- Memory.create_memory(agent, memory_params) do
      conn
      |> put_status(:created)
      |> json(%{memory: serialize_memory(memory)})
    end
  end

  @doc """
  POST /api/observations

  Records an observation (convenience endpoint).
  """
  def record_observation(conn, %{"content" => content} = params) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    opts =
      []
      |> maybe_add_opt(:importance, params["importance"], &parse_int/1)
      |> maybe_add_opt(:context, params["context"])

    with {:ok, memory} <- Memory.record_observation(agent, content, opts) do
      conn
      |> put_status(:created)
      |> json(%{memory: serialize_memory(memory)})
    end
  end

  @doc """
  POST /api/reflections

  Records a reflection (convenience endpoint).
  """
  def record_reflection(conn, %{"content" => content} = params) do
    {:ok, agent} = Agents.get_or_create_default_agent()

    opts =
      []
      |> maybe_add_opt(:importance, params["importance"], &parse_int/1)
      |> maybe_add_opt(:context, params["context"])
      |> maybe_add_opt(:belief_ids, params["belief_ids"])

    with {:ok, memory} <- Memory.record_reflection(agent, content, opts) do
      conn
      |> put_status(:created)
      |> json(%{memory: serialize_memory(memory)})
    end
  end

  @doc """
  GET /api/memories/:id

  Returns a specific memory.
  """
  def get_memory(conn, %{"id" => id}) do
    memory = Memory.get_memory!(id)
    json(conn, %{memory: serialize_memory(memory)})
  end

  # ============================================================================
  # Serializers
  # ============================================================================

  defp serialize_belief(belief) do
    %{
      id: belief.id,
      statement: belief.statement,
      source_evidence: belief.source_evidence,
      confidence: belief.confidence,
      entrenchment: belief.entrenchment,
      source_type: belief.source_type,
      status: belief.status,
      revision_count: belief.revision_count,
      contradicted_by_id: belief.contradicted_by_id,
      created_at: belief.inserted_at,
      updated_at: belief.updated_at
    }
  end

  defp serialize_question(question) do
    %{
      id: question.id,
      question: question.question,
      context: question.context,
      status: question.status,
      priority: question.priority,
      times_asked: question.times_asked,
      last_asked_at: question.last_asked_at,
      resolved_at: question.resolved_at,
      cluster_id: question.cluster_id,
      created_at: question.inserted_at
    }
  end

  defp serialize_finding(finding) do
    %{
      id: finding.id,
      answer: finding.answer,
      summary: finding.summary,
      source_type: finding.source_type,
      evidence: finding.evidence,
      confidence: finding.confidence,
      verified: finding.verified,
      verified_at: finding.verified_at,
      question_id: finding.question_id,
      created_at: finding.inserted_at
    }
  end

  defp serialize_memory(memory) do
    %{
      id: memory.id,
      content: memory.content,
      summary: memory.summary,
      memory_type: memory.memory_type,
      importance: memory.importance,
      access_count: memory.access_count,
      last_accessed_at: memory.last_accessed_at,
      source_context: memory.source_context,
      related_belief_ids: memory.related_belief_ids,
      created_at: memory.inserted_at
    }
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_opt(opts, _key, nil, _parser), do: opts

  defp maybe_add_opt(opts, key, value, parser) do
    case parser.(value) do
      nil -> opts
      parsed -> Keyword.put(opts, key, parsed)
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp parse_float(nil), do: nil
  defp parse_float(value) when is_float(value), do: value

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> nil
    end
  end
end
