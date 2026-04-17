defmodule Lincoln.Substrate.Resonator do
  @moduledoc """
  Coherence cascade detection in the belief graph.

  A "cascade" is when 3+ semantically similar beliefs cluster together with recent activity.
  This is the mechanism that makes Lincoln "get hooked on a topic":
  coherent belief clusters generate resonator flags that Attention weights more heavily.

  Uses embedding-based cosine similarity to form semantic clusters.
  Beliefs without embeddings are excluded.

  Called periodically by the Substrate tick loop — not a GenServer.
  """

  require Logger

  alias Lincoln.{Beliefs, PubSubBroadcaster}

  @min_cluster_size 3
  @cascade_window_hours 1
  @similarity_threshold 0.7
  @relationship_similarity_threshold 0.6
  @min_cascade_score 1.5

  @doc "Run one round of coherence cascade detection for the agent."
  def detect_cascades(agent) do
    beliefs =
      Beliefs.list_beliefs(agent, status: "active")
      |> Enum.filter(&(&1.embedding != nil))

    if length(beliefs) < @min_cluster_size do
      :ok
    else
      beliefs
      |> build_semantic_clusters()
      |> Enum.filter(&(length(&1) >= @min_cluster_size))
      |> Enum.each(&maybe_process_cascade(&1, agent))
    end
  end

  defp build_semantic_clusters(beliefs) do
    adjacency =
      for a <- beliefs, b <- beliefs, a.id < b.id, reduce: %{} do
        acc ->
          similarity = cosine_similarity(a.embedding, b.embedding)

          if similarity >= @similarity_threshold do
            acc
            |> Map.update(a.id, [b.id], &[b.id | &1])
            |> Map.update(b.id, [a.id], &[a.id | &1])
          else
            acc
          end
      end

    belief_map = Map.new(beliefs, &{&1.id, &1})
    find_connected_components(beliefs, adjacency, belief_map)
  end

  defp find_connected_components(beliefs, adjacency, belief_map) do
    {clusters, _visited} =
      Enum.reduce(beliefs, {[], MapSet.new()}, fn belief, {clusters, visited} ->
        if MapSet.member?(visited, belief.id) do
          {clusters, visited}
        else
          {component_ids, new_visited} =
            bfs([belief.id], MapSet.new([belief.id]), adjacency)

          component = Enum.map(component_ids, &Map.fetch!(belief_map, &1))
          {[component | clusters], MapSet.union(visited, new_visited)}
        end
      end)

    clusters
  end

  defp bfs([], visited, _adjacency), do: {MapSet.to_list(visited), visited}

  defp bfs(queue, visited, adjacency) do
    next_queue =
      Enum.flat_map(queue, fn id ->
        neighbors = Map.get(adjacency, id, [])
        Enum.filter(neighbors, &(not MapSet.member?(visited, &1)))
      end)
      |> Enum.uniq()

    new_visited = Enum.reduce(next_queue, visited, &MapSet.put(&2, &1))
    bfs(next_queue, new_visited, adjacency)
  end

  defp cosine_similarity(embedding_a, embedding_b)
       when is_list(embedding_a) and is_list(embedding_b) do
    if length(embedding_a) != length(embedding_b) or embedding_a == [] do
      0.0
    else
      dot =
        Enum.zip(embedding_a, embedding_b)
        |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)

      mag_a = :math.sqrt(Enum.reduce(embedding_a, 0.0, fn x, acc -> acc + x * x end))
      mag_b = :math.sqrt(Enum.reduce(embedding_b, 0.0, fn x, acc -> acc + x * x end))

      if mag_a == 0.0 or mag_b == 0.0, do: 0.0, else: dot / (mag_a * mag_b)
    end
  end

  defp cosine_similarity(%Pgvector{} = a, %Pgvector{} = b),
    do: cosine_similarity(Pgvector.to_list(a), Pgvector.to_list(b))

  defp cosine_similarity(_, _), do: 0.0

  defp maybe_process_cascade(cluster_beliefs, agent) do
    now = DateTime.utc_now()
    window = @cascade_window_hours * 3600

    recently_active =
      Enum.filter(cluster_beliefs, fn belief ->
        DateTime.diff(now, belief.updated_at, :second) <= window
      end)

    if length(recently_active) >= @min_cluster_size do
      process_cascade(recently_active, now, agent)
    end
  end

  defp process_cascade(cluster_beliefs, now, agent) do
    weighted_confidences =
      Enum.map(cluster_beliefs, fn belief ->
        age_seconds = DateTime.diff(now, belief.updated_at, :second)
        recency_weight = max(0.2, 1.0 - 0.8 * min(age_seconds / 3600.0, 1.0))
        belief.confidence * recency_weight
      end)

    cascade_score = Enum.sum(weighted_confidences)

    if cascade_score < @min_cascade_score do
      Logger.debug(
        "[Resonator #{agent.id}] Cluster of #{length(cluster_beliefs)} below threshold (#{Float.round(cascade_score, 2)})"
      )
    else
      create_cascade_relationships(cluster_beliefs, cascade_score, agent)
    end
  end

  defp create_cascade_relationships(cluster_beliefs, cascade_score, agent) do
    avg_confidence =
      Enum.sum(Enum.map(cluster_beliefs, & &1.confidence)) / length(cluster_beliefs)

    pairs = for a <- cluster_beliefs, b <- cluster_beliefs, a.id < b.id, do: {a, b}

    new_relationships =
      pairs
      |> Enum.filter(fn {a, b} ->
        cosine_similarity(a.embedding, b.embedding) >= @relationship_similarity_threshold and
          not Beliefs.relationship_exists?(agent, a.id, b.id, "supports")
      end)
      |> Enum.map(fn {a, b} ->
        pair_similarity = Float.round(cosine_similarity(a.embedding, b.embedding), 2)

        Beliefs.create_relationship(%{
          agent_id: agent.id,
          source_belief_id: a.id,
          target_belief_id: b.id,
          relationship_type: "supports",
          confidence: avg_confidence,
          detected_by: "resonator",
          evidence:
            "Resonator cascade: #{length(cluster_beliefs)} semantically similar beliefs (similarity #{pair_similarity})"
        })
      end)
      |> Enum.count(fn result -> match?({:ok, _}, result) end)

    if new_relationships > 0 do
      Logger.info(
        "[Resonator #{agent.id}] Cascade detected: #{length(cluster_beliefs)} beliefs, score #{Float.round(cascade_score, 2)}, #{new_relationships} relationships"
      )

      PubSubBroadcaster.broadcast_resonator_flag(
        agent.id,
        {:cascade_detected,
         %{
           belief_ids: Enum.map(cluster_beliefs, & &1.id),
           cascade_score: cascade_score,
           cluster_size: length(cluster_beliefs),
           relationships_created: new_relationships
         }}
      )
    end
  end
end
