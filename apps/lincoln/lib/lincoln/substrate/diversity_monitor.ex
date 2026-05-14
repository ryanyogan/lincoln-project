defmodule Lincoln.Substrate.DiversityMonitor do
  @moduledoc """
  Entropy-based diversity monitoring for the cognitive substrate.

  Measures two forms of Shannon entropy over recent cognitive focus:
  - Item entropy: frequency distribution over individual belief IDs
  - Topic entropy: frequency distribution over semantic clusters

  When entropy drops, applies graduated response from mild novelty
  boosting to aggressive belief suppression. Self-regulating — Lincoln
  notices its own monotony and gets restless.

  Called periodically by the Substrate tick loop — not a GenServer.
  """

  alias Lincoln.Adapters.Embeddings
  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Attention

  require Logger

  @min_focus_samples 5
  @cluster_similarity_threshold 0.7

  @doc """
  Check cognitive diversity of the recent focus history and adjust
  attention parameters based on Shannon entropy levels.

  Uses graduated response:
  - entropy >= 0.6: healthy
  - 0.35-0.59: mild boost
  - 0.15-0.34: moderate boost + entrenchment dampening
  - < 0.15: aggressive boost + dampening + belief suppression
  """
  def check_and_adjust(agent) do
    focus_ids = recent_focus_ids(agent)

    if length(focus_ids) < @min_focus_samples do
      Logger.debug("[DiversityMonitor] Only #{length(focus_ids)} focus samples — skipping check")

      {:ok, :insufficient_data}
    else
      embeddings = focus_embeddings(focus_ids)
      item_entropy = item_entropy(focus_ids)
      topic_entropy = topic_entropy(embeddings)
      entropy = min(item_entropy, topic_entropy)

      Logger.debug(
        "[DiversityMonitor] item_entropy=#{Float.round(item_entropy, 3)} " <>
          "topic_entropy=#{Float.round(topic_entropy, 3)} " <>
          "effective=#{Float.round(entropy, 3)} samples=#{length(focus_ids)}"
      )

      apply_graduated_response(agent, entropy, focus_ids)
    end
  rescue
    e ->
      Logger.debug("[DiversityMonitor] Check failed: #{Exception.message(e)}")
      {:error, :check_failed}
  end

  defp apply_graduated_response(agent, entropy, focus_ids) do
    cond do
      entropy >= 0.6 ->
        restore_if_boosted(agent)
        {:ok, entropy}

      entropy >= 0.35 ->
        apply_tier(agent, :mild, novelty: 0.5, dampening: 0.3)
        {:mild, entropy}

      entropy >= 0.15 ->
        apply_tier(agent, :moderate, novelty: 0.7, dampening: 0.6)
        {:moderate, entropy}

      true ->
        suppressed = top_focused_ids(focus_ids, 3)
        apply_tier(agent, :aggressive, novelty: 0.85, dampening: 0.9, suppress: suppressed)
        {:aggressive, entropy}
    end
  end

  defp apply_tier(agent, tier, opts) do
    current = agent.attention_params || %{}

    base_novelty =
      current["base_novelty_weight"] || current["novelty_weight"] || current[:novelty_weight] ||
        0.3

    updates =
      current
      |> Map.put("base_novelty_weight", base_novelty)
      |> Map.put("novelty_weight", Keyword.get(opts, :novelty))
      |> Map.put("entrenchment_dampening", Keyword.get(opts, :dampening))
      |> Map.put("suppressed_belief_ids", Keyword.get(opts, :suppress, []))

    Logger.info(
      "[DiversityMonitor] #{tier} response — novelty=#{opts[:novelty]} dampening=#{opts[:dampening]}"
    )

    Agents.update_agent(agent, %{attention_params: updates})
    signal_attention_reload(agent.id)
  end

  defp restore_if_boosted(agent) do
    current = agent.attention_params || %{}
    base = current["base_novelty_weight"]

    if base do
      Logger.info("[DiversityMonitor] Diversity recovered — restoring base params")

      restored =
        current
        |> Map.put("novelty_weight", base)
        |> Map.delete("base_novelty_weight")
        |> Map.put("entrenchment_dampening", 0.0)
        |> Map.put("suppressed_belief_ids", [])

      Agents.update_agent(agent, %{attention_params: restored})
      signal_attention_reload(agent.id)
    end
  end

  # Shannon entropy over belief-ID frequency, normalized to [0,1].
  # H = -sum(p_i * log2(p_i)), normalized by log2(unique_count).
  defp item_entropy([]), do: 1.0

  defp item_entropy(ids) do
    total = length(ids)
    freqs = Enum.frequencies(ids)
    unique = map_size(freqs)

    if unique <= 1 do
      0.0
    else
      raw_h =
        freqs
        |> Map.values()
        |> Enum.reduce(0.0, fn count, acc ->
          p = count / total
          acc - p * :math.log2(p)
        end)

      raw_h / :math.log2(unique)
    end
  end

  # Shannon entropy over semantic clusters. Cluster focused beliefs by
  # embedding similarity using single-linkage, then compute entropy over
  # cluster sizes.
  defp topic_entropy(embeddings) when length(embeddings) < 3, do: 1.0

  defp topic_entropy(embeddings) do
    clusters = single_linkage_cluster(embeddings, @cluster_similarity_threshold)
    cluster_count = length(clusters)

    if cluster_count <= 1 do
      0.0
    else
      total = Enum.sum(Enum.map(clusters, &length/1))

      raw_h =
        clusters
        |> Enum.reduce(0.0, fn cluster, acc ->
          p = length(cluster) / total
          acc - p * :math.log2(p)
        end)

      raw_h / :math.log2(cluster_count)
    end
  end

  defp single_linkage_cluster(embeddings, threshold) do
    embeddings_adapter = embeddings_adapter()
    indexed = Enum.with_index(embeddings)

    adjacency =
      for {e1, i} <- indexed, {e2, j} <- indexed, i < j, reduce: %{} do
        acc ->
          if embeddings_adapter.similarity(e1, e2) >= threshold do
            acc
            |> Map.update(i, MapSet.new([j]), &MapSet.put(&1, j))
            |> Map.update(j, MapSet.new([i]), &MapSet.put(&1, i))
          else
            acc
          end
      end

    all_indices = MapSet.new(0..(length(embeddings) - 1))
    bfs_clusters(adjacency, all_indices, [])
  end

  defp bfs_clusters(_adj, remaining, clusters) when remaining == %MapSet{} do
    clusters
  end

  defp bfs_clusters(adj, remaining, clusters) do
    if MapSet.size(remaining) == 0 do
      clusters
    else
      start = remaining |> MapSet.to_list() |> hd()
      cluster = bfs(adj, start, MapSet.new())
      new_remaining = MapSet.difference(remaining, cluster)
      bfs_clusters(adj, new_remaining, [MapSet.to_list(cluster) | clusters])
    end
  end

  defp bfs(adj, node, visited) do
    if MapSet.member?(visited, node) do
      visited
    else
      visited = MapSet.put(visited, node)
      neighbors = Map.get(adj, node, MapSet.new())

      Enum.reduce(neighbors, visited, fn neighbor, acc ->
        bfs(adj, neighbor, acc)
      end)
    end
  end

  # Returns the N most frequently focused belief IDs.
  defp top_focused_ids(focus_ids, n) do
    focus_ids
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_id, count} -> -count end)
    |> Enum.take(n)
    |> Enum.map(fn {id, _count} -> id end)
  end

  defp recent_focus_ids(agent) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent.id, :attention}) do
      [{pid, _}] ->
        try do
          Attention.recent_focus_ids(pid) || []
        catch
          :exit, _ -> []
        end

      [] ->
        []
    end
  end

  defp focus_embeddings(focus_ids) do
    focus_ids
    |> Enum.uniq()
    |> Enum.map(&safe_get_belief/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.embedding)
    |> Enum.reject(&is_nil/1)
  end

  defp safe_get_belief(id) do
    Beliefs.get_belief!(id)
  rescue
    Ecto.NoResultsError -> nil
    _ -> nil
  end

  defp signal_attention_reload(agent_id) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, :attention}) do
      [{pid, _}] -> GenServer.cast(pid, {:reload_params})
      [] -> :ok
    end
  end

  defp embeddings_adapter do
    Application.get_env(:lincoln, :embeddings_adapter, Embeddings.PythonService)
  end
end
