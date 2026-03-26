defmodule Lincoln.Questions do
  @moduledoc """
  The Questions context.

  Manages questions, findings, interests, and the curiosity system.
  Includes loop detection to prevent repetitive questioning.
  """
  import Ecto.Query
  alias Lincoln.Repo
  alias Lincoln.Questions.{Question, QuestionCluster, Finding, Interest, ActionLog}
  alias Lincoln.Agents.Agent
  alias Lincoln.PubSubBroadcaster

  # ============================================================================
  # Questions
  # ============================================================================

  @doc """
  Returns all open questions for an agent.
  """
  def list_open_questions(%Agent{id: agent_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Question
    |> where([q], q.agent_id == ^agent_id and q.status == "open")
    |> order_by([q], desc: q.priority, asc: q.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns questions ready for investigation.
  """
  def list_investigatable_questions(%Agent{id: agent_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    now = DateTime.utc_now()

    Question
    |> where([q], q.agent_id == ^agent_id and q.status == "open")
    |> where([q], is_nil(q.investigate_after) or q.investigate_after <= ^now)
    |> order_by([q], desc: q.priority, asc: q.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns all questions for an agent with optional filters.
  """
  def list_questions(%Agent{id: agent_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    query =
      Question
      |> where([q], q.agent_id == ^agent_id)

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> where(query, [q], q.status == ^status)
      end

    query
    |> order_by([q], desc: q.priority, desc: q.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single question.
  """
  def get_question!(id), do: Repo.get!(Question, id)

  @doc """
  Creates a new question, checking for duplicates first.
  """
  def ask_question(%Agent{id: agent_id} = agent, question_text, opts \\ []) do
    semantic_hash = Keyword.get(opts, :semantic_hash)
    embedding = Keyword.get(opts, :embedding)

    # Check for existing similar question using semantic hash
    result =
      case find_similar_question(agent, semantic_hash, embedding) do
        nil ->
          # New question
          %Question{}
          |> Question.create_changeset(
            %{
              question: question_text,
              context: Keyword.get(opts, :context),
              semantic_hash: semantic_hash,
              embedding: embedding,
              priority: Keyword.get(opts, :priority, 5)
            },
            agent_id
          )
          |> Repo.insert()

        existing ->
          # Duplicate detected - increment counter instead of creating new
          existing
          |> Question.asked_again_changeset()
          |> Repo.update()
      end

    case result do
      {:ok, question} ->
        PubSubBroadcaster.broadcast_question_created(agent_id, question)
        {:ok, question}

      error ->
        error
    end
  end

  @doc """
  Finds a similar question using semantic hash or embedding.
  """
  def find_similar_question(%Agent{id: agent_id}, semantic_hash, embedding) do
    # First try exact hash match
    hash_match =
      if semantic_hash do
        Question
        |> where([q], q.agent_id == ^agent_id and q.semantic_hash == ^semantic_hash)
        |> where([q], q.status in ["open", "answered"])
        |> Repo.one()
      end

    if hash_match do
      hash_match
    else
      # Fall back to embedding similarity if we have one
      if embedding do
        find_semantically_similar_question(agent_id, embedding)
      end
    end
  end

  defp find_semantically_similar_question(agent_id, embedding) do
    # Convert UUID string to binary for raw SQL query
    {:ok, agent_id_binary} = Ecto.UUID.dump(agent_id)

    query = """
    SELECT q.*
    FROM questions q
    WHERE q.agent_id = $1
      AND q.status IN ('open', 'answered')
      AND q.embedding IS NOT NULL
      AND 1 - (q.embedding <=> $2::vector) >= 0.9
    ORDER BY 1 - (q.embedding <=> $2::vector) DESC
    LIMIT 1
    """

    case Repo.query(query, [agent_id_binary, embedding]) do
      {:ok, %{rows: [row | _], columns: columns}} ->
        columns
        |> Enum.map(&String.to_atom/1)
        |> Enum.zip(row)
        |> Map.new()
        |> then(&struct(Question, &1))

      _ ->
        nil
    end
  end

  @doc """
  Resolves a question with a finding.
  """
  def resolve_question(%Question{} = question, %Finding{} = finding) do
    question
    |> Question.resolve_changeset(finding.id)
    |> Repo.update()
  end

  @doc """
  Abandons a question.
  """
  def abandon_question(%Question{} = question) do
    result =
      question
      |> Question.abandon_changeset()
      |> Repo.update()

    case result do
      {:ok, updated} ->
        PubSubBroadcaster.broadcast_question_updated(question.agent_id, updated)
        {:ok, updated}

      error ->
        error
    end
  end

  # ============================================================================
  # Findings
  # ============================================================================

  @doc """
  Creates a finding that answers a question.
  """
  def create_finding(%Agent{id: agent_id}, %Question{id: question_id}, attrs) do
    result =
      Repo.transaction(fn ->
        # Create the finding
        {:ok, finding} =
          %Finding{}
          |> Finding.create_changeset(attrs, agent_id, question_id)
          |> Repo.insert()

        # Resolve the question
        question = get_question!(question_id)
        {:ok, resolved_question} = resolve_question(question, finding)

        {finding, resolved_question}
      end)

    case result do
      {:ok, {finding, resolved_question}} ->
        PubSubBroadcaster.broadcast_finding_created(agent_id, finding)
        PubSubBroadcaster.broadcast_question_resolved(agent_id, resolved_question, finding)
        {:ok, finding}

      error ->
        error
    end
  end

  @doc """
  Creates a finding without a specific question (serendipitous discovery).
  """
  def create_serendipitous_finding(%Agent{id: agent_id}, attrs) do
    %Finding{}
    |> Finding.create_changeset(Map.put(attrs, :source_type, "serendipity"), agent_id, nil)
    |> Repo.insert()
  end

  @doc """
  Verifies a finding.
  """
  def verify_finding(%Finding{} = finding) do
    finding
    |> Finding.verify_changeset()
    |> Repo.update()
  end

  @doc """
  Lists findings for a question.
  """
  def list_findings_for_question(%Question{id: question_id}) do
    Finding
    |> where([f], f.question_id == ^question_id)
    |> order_by([f], desc: f.confidence, desc: f.inserted_at)
    |> Repo.all()
  end

  # ============================================================================
  # Question Clusters
  # ============================================================================

  @doc """
  Returns all active clusters for an agent.
  """
  def list_clusters(%Agent{id: agent_id}) do
    QuestionCluster
    |> where([c], c.agent_id == ^agent_id and c.status == "active")
    |> order_by([c], desc: c.question_count)
    |> Repo.all()
  end

  @doc """
  Creates a new question cluster.
  """
  def create_cluster(%Agent{id: agent_id}, attrs) do
    %QuestionCluster{}
    |> QuestionCluster.create_changeset(attrs, agent_id)
    |> Repo.insert()
  end

  @doc """
  Assigns a question to a cluster.
  """
  def assign_to_cluster(%Question{} = question, %QuestionCluster{} = cluster) do
    Repo.transaction(fn ->
      # Update question
      {:ok, updated_question} =
        question
        |> Ecto.Changeset.change(cluster_id: cluster.id)
        |> Repo.update()

      # Update cluster count
      count =
        Question
        |> where([q], q.cluster_id == ^cluster.id)
        |> Repo.aggregate(:count)

      {:ok, _} =
        cluster
        |> QuestionCluster.update_count_changeset(count)
        |> Repo.update()

      updated_question
    end)
  end

  # ============================================================================
  # Interests
  # ============================================================================

  @doc """
  Returns all active interests for an agent.
  """
  def list_interests(%Agent{id: agent_id}) do
    Interest
    |> where([i], i.agent_id == ^agent_id and i.status == "active")
    |> order_by([i], desc: i.intensity)
    |> Repo.all()
  end

  @doc """
  Creates a new interest.
  """
  def create_interest(%Agent{id: agent_id}, attrs) do
    %Interest{}
    |> Interest.create_changeset(attrs, agent_id)
    |> Repo.insert()
  end

  @doc """
  Records that an interest was explored.
  """
  def explore_interest(%Interest{} = interest) do
    interest
    |> Interest.explore_changeset()
    |> Repo.update()
  end

  # ============================================================================
  # Action Log
  # ============================================================================

  @doc """
  Logs an action.
  """
  def log_action(%Agent{id: agent_id}, action_type, attrs \\ %{}) do
    %ActionLog{}
    |> ActionLog.create_changeset(Map.put(attrs, :action_type, action_type), agent_id)
    |> Repo.insert()
  end

  @doc """
  Completes an action log entry.
  """
  def complete_action(%ActionLog{} = action_log, outcome, details \\ nil) do
    action_log
    |> ActionLog.complete_changeset(outcome, details)
    |> Repo.update()
  end

  @doc """
  Detects if an action pattern is repeating (loop detection).
  """
  def detect_action_loop(%Agent{id: agent_id}, semantic_hash, window_hours \\ 24) do
    cutoff = DateTime.add(DateTime.utc_now(), -window_hours * 3600, :second)

    count =
      ActionLog
      |> where([a], a.agent_id == ^agent_id)
      |> where([a], a.semantic_hash == ^semantic_hash)
      |> where([a], a.inserted_at >= ^cutoff)
      |> Repo.aggregate(:count)

    # If the same action hash appears more than 3 times in the window, it's a loop
    count >= 3
  end

  @doc """
  Returns recent actions for pattern analysis.
  """
  def list_recent_actions(%Agent{id: agent_id}, hours \\ 24, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    ActionLog
    |> where([a], a.agent_id == ^agent_id and a.inserted_at >= ^cutoff)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
