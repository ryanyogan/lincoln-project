defmodule Lincoln.Memory do
  @moduledoc """
  The Memory context.

  Manages memory storage, retrieval, and the reflection process.
  Implements a retrieval system based on the Generative Agents paper.
  """
  import Ecto.Query
  alias Lincoln.Repo
  alias Lincoln.Memory.Memory
  alias Lincoln.Agents.Agent
  alias Lincoln.PubSubBroadcaster

  # ============================================================================
  # Memory CRUD
  # ============================================================================

  @doc """
  Returns all memories for an agent, ordered by recency.

  Options:
  - `:limit` - max number of results
  - `:memory_type` - filter by type
  - `:min_importance` - filter by minimum importance
  """
  def list_memories(%Agent{id: agent_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    query =
      Memory
      |> where([m], m.agent_id == ^agent_id)

    query =
      case Keyword.get(opts, :memory_type) do
        nil -> query
        type -> where(query, [m], m.memory_type == ^type)
      end

    query =
      case Keyword.get(opts, :min_importance) do
        nil -> query
        min -> where(query, [m], m.importance >= ^min)
      end

    query
    |> order_by([m], desc: m.inserted_at)
    |> offset(^offset)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns memories of a specific type.
  """
  def list_memories_by_type(%Agent{id: agent_id}, memory_type, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Memory
    |> where([m], m.agent_id == ^agent_id and m.memory_type == ^memory_type)
    |> order_by([m], desc: m.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns recent memories (last N hours).
  """
  def list_recent_memories(%Agent{id: agent_id}, hours \\ 24, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    Memory
    |> where([m], m.agent_id == ^agent_id and m.inserted_at >= ^cutoff)
    |> order_by([m], desc: m.inserted_at)
    |> offset(^offset)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets a single memory.
  """
  def get_memory!(id), do: Repo.get!(Memory, id)

  @doc """
  Creates a new memory for an agent.
  """
  def create_memory(%Agent{id: agent_id}, attrs) do
    result =
      %Memory{}
      |> Memory.create_changeset(attrs, agent_id)
      |> Repo.insert()

    case result do
      {:ok, memory} ->
        PubSubBroadcaster.broadcast_memory_created(agent_id, memory)
        {:ok, memory}

      error ->
        error
    end
  end

  @doc """
  Creates an observation memory.
  """
  def record_observation(%Agent{} = agent, content, opts \\ []) do
    create_memory(agent, %{
      content: content,
      memory_type: "observation",
      importance: Keyword.get(opts, :importance, 5),
      source_context: Keyword.get(opts, :context, %{}),
      embedding: Keyword.get(opts, :embedding)
    })
  end

  @doc """
  Creates a reflection memory.
  """
  def record_reflection(%Agent{} = agent, content, opts \\ []) do
    create_memory(agent, %{
      content: content,
      memory_type: "reflection",
      importance: Keyword.get(opts, :importance, 7),
      source_context: Keyword.get(opts, :context, %{}),
      related_belief_ids: Keyword.get(opts, :belief_ids, []),
      embedding: Keyword.get(opts, :embedding)
    })
  end

  @doc """
  Creates a conversation memory.
  """
  def record_conversation(%Agent{} = agent, content, opts \\ []) do
    create_memory(agent, %{
      content: content,
      memory_type: "conversation",
      importance: Keyword.get(opts, :importance, 5),
      source_context: Keyword.get(opts, :context, %{}),
      embedding: Keyword.get(opts, :embedding)
    })
  end

  # ============================================================================
  # Memory Retrieval
  # ============================================================================

  @doc """
  Retrieves relevant memories using a weighted scoring function.

  Score = α * recency + β * importance + γ * relevance

  Where:
  - recency: exponential decay based on time since creation
  - importance: normalized importance score (1-10 -> 0.1-1.0)
  - relevance: cosine similarity to query embedding
  """
  def retrieve_memories(%Agent{id: agent_id}, query_embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    recency_weight = Keyword.get(opts, :recency_weight, 1.0)
    importance_weight = Keyword.get(opts, :importance_weight, 1.0)
    relevance_weight = Keyword.get(opts, :relevance_weight, 1.0)

    # Convert UUID string to binary for raw SQL query
    {:ok, agent_id_binary} = Ecto.UUID.dump(agent_id)

    # Use raw SQL for the complex scoring function
    query = """
    WITH scored_memories AS (
      SELECT
        m.*,
        -- Recency score: exponential decay (half-life of 24 hours)
        EXP(-EXTRACT(EPOCH FROM (NOW() - m.inserted_at)) / 86400.0) as recency_score,
        -- Importance score: normalized to 0-1
        m.importance / 10.0 as importance_score,
        -- Relevance score: cosine similarity
        CASE
          WHEN m.embedding IS NOT NULL THEN 1 - (m.embedding <=> $1::vector)
          ELSE 0
        END as relevance_score
      FROM memories m
      WHERE m.agent_id = $2
    )
    SELECT *,
      ($3 * recency_score + $4 * importance_score + $5 * relevance_score) as total_score
    FROM scored_memories
    ORDER BY total_score DESC
    LIMIT $6
    """

    result =
      Repo.query!(query, [
        query_embedding,
        agent_id_binary,
        recency_weight,
        importance_weight,
        relevance_weight,
        limit
      ])

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

  @doc """
  Finds memories similar to a given embedding.
  """
  def find_similar_memories(%Agent{id: agent_id}, embedding, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    threshold = Keyword.get(opts, :threshold, 0.7)

    # Convert UUID string to binary for raw SQL query
    {:ok, agent_id_binary} = Ecto.UUID.dump(agent_id)

    query = """
    SELECT m.*, 1 - (m.embedding <=> $1::vector) as similarity
    FROM memories m
    WHERE m.agent_id = $2
      AND m.embedding IS NOT NULL
      AND 1 - (m.embedding <=> $1::vector) >= $3
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

  # ============================================================================
  # Memory Access Tracking
  # ============================================================================

  @doc """
  Records that a memory was accessed (for retrieval scoring).
  """
  def touch_memory(%Memory{} = memory) do
    result =
      memory
      |> Memory.access_changeset()
      |> Repo.update()

    case result do
      {:ok, updated} ->
        PubSubBroadcaster.broadcast_memory_updated(memory.agent_id, updated)
        {:ok, updated}

      error ->
        error
    end
  end
end
