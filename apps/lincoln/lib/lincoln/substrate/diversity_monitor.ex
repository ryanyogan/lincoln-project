defmodule Lincoln.Substrate.DiversityMonitor do
  @moduledoc """
  Entropy-based diversity monitoring for the cognitive substrate.

  Continuously measures the semantic diversity of recent cognitive output.
  When diversity drops below a threshold (perseveration), temporarily boosts
  novelty_weight in attention parameters to force exploration. When diversity
  recovers, returns to base parameters.

  This is a self-regulating mechanism — Lincoln notices it has been thinking
  the same kinds of things and gets restless. From the GWA cognitive
  architecture paper's approach to preventing stagnation.

  Called periodically by the Substrate tick loop — not a GenServer.
  """

  alias Lincoln.Adapters.Embeddings
  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Attention

  require Logger

  @diversity_threshold 0.3
  @boosted_novelty 0.7
  @min_focus_samples 5

  @doc """
  Check cognitive diversity of the recent *focus* history (what
  Attention has actually been selecting) and adjust attention
  parameters if diversity is too low.

  Sampling the focus history rather than the belief table is what makes
  this work — a fresh batch of incoming RSS observations would inflate
  recency-sampled diversity to near 1.0 even while Attention is in fact
  cycling on the same five high-tension items.
  """
  def check_and_adjust(agent) do
    focus_ids = recent_focus_ids(agent)

    if length(focus_ids) < @min_focus_samples do
      Logger.debug(
        "[DiversityMonitor] Only #{length(focus_ids)} focus samples — skipping check"
      )

      {:ok, :insufficient_data}
    else
      embeddings = focus_embeddings(focus_ids)
      diversity = compute_diversity(embeddings)
      perseveration = perseveration_ratio(focus_ids)

      Logger.debug(
        "[DiversityMonitor] focus diversity=#{Float.round(diversity, 3)} " <>
          "unique_ratio=#{Float.round(perseveration, 3)} " <>
          "samples=#{length(focus_ids)}"
      )

      # Trip on either signal: low semantic spread OR high repetition.
      # Repetition alone (e.g. cycling between 3 distinct beliefs) won't
      # always tank the cosine-distance average if those beliefs are
      # semantically far apart, so we need both signals.
      if diversity < @diversity_threshold or perseveration < 0.4 do
        boost_novelty(agent)
        {:low, diversity}
      else
        restore_if_boosted(agent)
        {:ok, diversity}
      end
    end
  rescue
    e ->
      Logger.debug("[DiversityMonitor] Check failed: #{Exception.message(e)}")
      {:error, :check_failed}
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

  # Ratio of unique focus IDs to total focus events. 1.0 means every
  # focus was a distinct belief; 0.2 means Lincoln cycled through the
  # same single belief most of the window. Independent of embedding
  # similarity — catches structural perseveration even when beliefs are
  # semantically far apart.
  defp perseveration_ratio([]), do: 1.0

  defp perseveration_ratio(ids) do
    length(Enum.uniq(ids)) / length(ids)
  end

  defp compute_diversity(embeddings) when length(embeddings) < 3, do: 1.0

  defp compute_diversity(embeddings) do
    embeddings_adapter = embeddings_adapter()

    pairs =
      for {e1, i} <- Enum.with_index(embeddings),
          {e2, j} <- Enum.with_index(embeddings),
          i < j,
          do: {e1, e2}

    if pairs == [] do
      1.0
    else
      distances =
        Enum.map(pairs, fn {e1, e2} ->
          1.0 - embeddings_adapter.similarity(e1, e2)
        end)

      Enum.sum(distances) / length(distances)
    end
  end

  defp boost_novelty(agent) do
    current = agent.attention_params || %{}
    base = current["novelty_weight"] || current[:novelty_weight] || 0.3

    # Only boost if not already boosted
    if base < @boosted_novelty do
      Logger.info(
        "[DiversityMonitor] Low diversity — boosting novelty_weight to #{@boosted_novelty}"
      )

      boosted =
        current
        |> Map.put("base_novelty_weight", base)
        |> Map.put("novelty_weight", @boosted_novelty)

      Agents.update_agent(agent, %{attention_params: boosted})
      signal_attention_reload(agent.id)
    end
  end

  defp restore_if_boosted(agent) do
    current = agent.attention_params || %{}
    base = current["base_novelty_weight"]

    if base do
      Logger.info("[DiversityMonitor] Diversity recovered — restoring novelty_weight to #{base}")

      restored =
        current
        |> Map.put("novelty_weight", base)
        |> Map.delete("base_novelty_weight")

      Agents.update_agent(agent, %{attention_params: restored})
      signal_attention_reload(agent.id)
    end
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
