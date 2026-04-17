defmodule Lincoln.Beliefs do
  @moduledoc """
  The Beliefs context.

  Manages belief formation, revision, and querying.
  Implements concepts from the AGM belief revision framework.
  """
  import Ecto.Query
  alias Lincoln.Agents.Agent
  alias Lincoln.Beliefs.{Belief, BeliefRelationship, BeliefRevision}
  alias Lincoln.PubSubBroadcaster
  alias Lincoln.Repo

  # ============================================================================
  # Belief CRUD
  # ============================================================================

  @doc """
  Returns all active beliefs for an agent.

  Options:
  - `:min_confidence` - filter by minimum confidence
  - `:max_confidence` - filter by maximum confidence
  - `:status` - filter by status
  - `:limit` - limit results
  - `:offset` - offset results
  - `:order_by` - custom ordering (e.g. `[asc: :updated_at]`), defaults to `[desc: :confidence]`
  """
  def list_beliefs(%Agent{id: agent_id}, opts \\ []) do
    Belief
    |> where([b], b.agent_id == ^agent_id)
    |> apply_status_filter(opts)
    |> apply_confidence_filters(opts)
    |> apply_pagination(opts)
    |> apply_ordering(opts)
    |> Repo.all()
  end

  defp apply_status_filter(query, opts) do
    case Keyword.get(opts, :status) do
      nil -> where(query, [b], b.status == "active")
      status -> where(query, [b], b.status == ^status)
    end
  end

  defp apply_confidence_filters(query, opts) do
    query =
      case Keyword.get(opts, :min_confidence) do
        nil -> query
        min -> where(query, [b], b.confidence >= ^min)
      end

    case Keyword.get(opts, :max_confidence) do
      nil -> query
      max -> where(query, [b], b.confidence <= ^max)
    end
  end

  defp apply_pagination(query, opts) do
    query =
      case Keyword.get(opts, :offset) do
        nil -> query
        offset_val -> offset(query, ^offset_val)
      end

    case Keyword.get(opts, :limit) do
      nil -> query
      limit_val -> limit(query, ^limit_val)
    end
  end

  defp apply_ordering(query, opts) do
    case Keyword.get(opts, :order_by) do
      nil -> order_by(query, [b], desc: b.confidence)
      ordering -> order_by(query, ^ordering)
    end
  end

  @doc """
  Returns beliefs by source type.
  """
  def list_beliefs_by_source(%Agent{id: agent_id}, source_type) do
    Belief
    |> where(
      [b],
      b.agent_id == ^agent_id and b.source_type == ^source_type and b.status == "active"
    )
    |> order_by([b], desc: b.confidence)
    |> Repo.all()
  end

  @doc """
  Returns the most entrenched beliefs (core beliefs).
  """
  def list_core_beliefs(%Agent{id: agent_id}, limit \\ 10) do
    Belief
    |> where([b], b.agent_id == ^agent_id and b.status == "active")
    |> order_by([b], desc: b.entrenchment, desc: b.confidence)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single belief.
  """
  def get_belief!(id), do: Repo.get!(Belief, id)

  @doc """
  Creates a new belief for an agent.
  """
  def create_belief(%Agent{id: agent_id}, attrs) do
    result =
      %Belief{}
      |> Belief.create_changeset(attrs, agent_id)
      |> Repo.insert()

    case result do
      {:ok, belief} ->
        PubSubBroadcaster.broadcast_belief_created(agent_id, belief)
        {:ok, belief}

      error ->
        error
    end
  end

  @doc """
  Updates a belief.
  """
  def update_belief(%Belief{} = belief, attrs) do
    result =
      belief
      |> Belief.changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated} ->
        PubSubBroadcaster.broadcast_belief_updated(belief.agent_id, updated)
        {:ok, updated}

      error ->
        error
    end
  end

  # ============================================================================
  # Belief Revision (AGM Framework)
  # ============================================================================

  @doc """
  Increases a belief's entrenchment — it becomes harder to revise.
  Called when a belief is repeatedly thought about and reinforced.
  """
  def entrench_belief(%Belief{} = belief, amount \\ 1) do
    new_entrenchment = min(10, belief.entrenchment + amount)
    update_belief(belief, %{entrenchment: new_entrenchment})
  end

  @doc """
  Strengthens a belief when supporting evidence is found.
  """
  def strengthen_belief(%Belief{} = belief, evidence, opts \\ []) do
    boost = Keyword.get(opts, :boost, 0.1)
    new_confidence = min(1.0, belief.confidence + boost)

    Repo.transaction(fn ->
      # Record the revision
      {:ok, _revision} =
        create_revision(belief, %{
          revision_type: "strengthened",
          new_confidence: new_confidence,
          trigger_type: Keyword.get(opts, :trigger_type, "observation"),
          trigger_evidence: evidence,
          trigger_memory_id: Keyword.get(opts, :memory_id),
          reasoning: "Supporting evidence found: #{evidence}"
        })

      # Update the belief
      {:ok, updated} =
        belief
        |> Belief.revise_confidence_changeset(new_confidence, evidence)
        |> Repo.update()

      updated
    end)
  end

  @doc """
  Weakens a belief when contradicting evidence is found (but not enough to retract).
  """
  def weaken_belief(%Belief{} = belief, evidence, opts \\ []) do
    penalty = Keyword.get(opts, :penalty, 0.1)
    new_confidence = max(0.0, belief.confidence - penalty)

    Repo.transaction(fn ->
      {:ok, _revision} =
        create_revision(belief, %{
          revision_type: "weakened",
          new_confidence: new_confidence,
          trigger_type: Keyword.get(opts, :trigger_type, "contradiction"),
          trigger_evidence: evidence,
          trigger_memory_id: Keyword.get(opts, :memory_id),
          reasoning: "Contradicting evidence found: #{evidence}"
        })

      {:ok, updated} =
        belief
        |> Belief.revise_confidence_changeset(new_confidence, evidence)
        |> Repo.update()

      updated
    end)
  end

  @doc """
  Retracts a belief entirely.
  """
  def retract_belief(%Belief{} = belief, reason, opts \\ []) do
    Repo.transaction(fn ->
      {:ok, _revision} =
        create_revision(belief, %{
          revision_type: "retracted",
          new_confidence: 0.0,
          trigger_type: Keyword.get(opts, :trigger_type, "contradiction"),
          trigger_evidence: reason,
          reasoning: "Belief retracted: #{reason}"
        })

      {:ok, updated} =
        belief
        |> Belief.retract_changeset()
        |> Repo.update()

      updated
    end)
  end

  @doc """
  Supersedes a belief with a new, more accurate one.
  """
  def supersede_belief(%Belief{} = old_belief, new_belief_attrs, reason) do
    Repo.transaction(fn ->
      # Create the new belief
      {:ok, new_belief} = create_belief(%Agent{id: old_belief.agent_id}, new_belief_attrs)

      # Mark old belief as superseded
      {:ok, _revision} =
        create_revision(old_belief, %{
          revision_type: "superseded",
          new_confidence: old_belief.confidence,
          trigger_type: "inference",
          trigger_evidence: reason,
          reasoning: "Superseded by more accurate belief"
        })

      {:ok, _updated} =
        old_belief
        |> Belief.contradict_changeset(new_belief.id)
        |> Repo.update()

      new_belief
    end)
  end

  # ============================================================================
  # Belief Revision Records
  # ============================================================================

  @doc """
  Creates a belief revision record.
  """
  def create_revision(%Belief{} = belief, attrs) do
    %BeliefRevision{}
    |> BeliefRevision.create_changeset(attrs, belief, belief.agent_id)
    |> Repo.insert()
  end

  @doc """
  Returns revision history for a belief.
  """
  def list_revisions(%Belief{id: belief_id}) do
    BeliefRevision
    |> where([r], r.belief_id == ^belief_id)
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  # ============================================================================
  # Semantic Search
  # ============================================================================

  @doc """
  Finds beliefs similar to a given embedding.
  """
  def find_similar_beliefs(%Agent{id: agent_id}, embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.7)

    # Convert UUID string to binary for raw SQL query
    {:ok, agent_id_binary} = Ecto.UUID.dump(agent_id)

    query = """
    SELECT b.*, 1 - (b.embedding <=> $1::vector) as similarity
    FROM beliefs b
    WHERE b.agent_id = $2
      AND b.status = 'active'
      AND b.embedding IS NOT NULL
      AND 1 - (b.embedding <=> $1::vector) >= $3
    ORDER BY similarity DESC
    LIMIT $4
    """

    result = Repo.query!(query, [embedding, agent_id_binary, threshold, limit])

    columns = Enum.map(result.columns, &String.to_atom/1)

    Enum.map(result.rows, fn row ->
      row_map =
        columns
        |> Enum.zip(row)
        |> Map.new()

      # Convert binary UUIDs back to string format for Ecto compatibility
      row_map
      |> maybe_convert_uuid(:id)
      |> maybe_convert_uuid(:agent_id)
    end)
  end

  # Helper to convert binary UUID to string format
  defp maybe_convert_uuid(map, key) do
    case Map.get(map, key) do
      <<_::binary-size(16)>> = binary_uuid ->
        {:ok, string_uuid} = Ecto.UUID.load(binary_uuid)
        Map.put(map, key, string_uuid)

      _ ->
        map
    end
  end

  @doc """
  Finds beliefs that might contradict a given statement.
  """
  def find_potential_contradictions(%Agent{} = agent, embedding, opts \\ []) do
    # This is a heuristic - beliefs that are semantically similar
    # but have different source types or low confidence might contradict
    find_similar_beliefs(agent, embedding, opts)
  end

  # ============================================================================
  # Belief Relationships
  # ============================================================================

  @doc """
  Creates a new relationship between two beliefs.
  """
  def create_relationship(attrs) do
    %BeliefRelationship{}
    |> BeliefRelationship.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Finds all relationships connected to a belief (both incoming and outgoing).
  """
  def find_relationships(%Agent{id: agent_id}, belief_id) do
    BeliefRelationship
    |> where([r], r.agent_id == ^agent_id)
    |> where([r], r.source_belief_id == ^belief_id or r.target_belief_id == ^belief_id)
    |> Repo.all()
  end

  @doc """
  Finds all contradictions for an agent.
  """
  def find_contradictions(%Agent{id: agent_id}) do
    BeliefRelationship
    |> where([r], r.agent_id == ^agent_id)
    |> where([r], r.relationship_type == "contradicts")
    |> preload([:source_belief, :target_belief])
    |> Repo.all()
  end

  @doc """
  Finds all beliefs in a support cluster (connected by "supports" relationships).
  """
  def find_support_cluster(%Agent{id: agent_id}, belief_id) do
    BeliefRelationship
    |> where([r], r.agent_id == ^agent_id)
    |> where([r], r.relationship_type == "supports")
    |> where([r], r.source_belief_id == ^belief_id or r.target_belief_id == ^belief_id)
    |> preload([:source_belief, :target_belief])
    |> Repo.all()
  end

  @doc """
  Returns all belief relationships for an agent.

  Used by Attention to pre-load relationships in bulk (avoiding N+1 queries).
  """
  def find_all_relationships(%Agent{id: agent_id}) do
    BeliefRelationship
    |> where([r], r.agent_id == ^agent_id)
    |> preload([:source_belief, :target_belief])
    |> Repo.all()
  end

  @doc """
  Checks if a relationship already exists between two beliefs.
  """
  def relationship_exists?(%Agent{id: agent_id}, source_id, target_id, type) do
    BeliefRelationship
    |> where([r], r.agent_id == ^agent_id)
    |> where([r], r.source_belief_id == ^source_id)
    |> where([r], r.target_belief_id == ^target_id)
    |> where([r], r.relationship_type == ^type)
    |> Repo.exists?()
  end
end
