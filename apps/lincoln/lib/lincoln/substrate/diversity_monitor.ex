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

  require Logger

  @diversity_threshold 0.3
  @boosted_novelty 0.7

  @doc """
  Check cognitive diversity of recent focus history and adjust attention
  parameters if diversity is too low.
  """
  def check_and_adjust(agent) do
    embeddings = get_recent_focus_embeddings(agent, limit: 15)
    diversity = compute_diversity(embeddings)

    Logger.debug("[DiversityMonitor] Diversity score: #{Float.round(diversity, 3)}")

    if diversity < @diversity_threshold do
      boost_novelty(agent)
      {:low, diversity}
    else
      restore_if_boosted(agent)
      {:ok, diversity}
    end
  rescue
    e ->
      Logger.debug("[DiversityMonitor] Check failed: #{Exception.message(e)}")
      {:error, :check_failed}
  end

  defp get_recent_focus_embeddings(agent, opts) do
    limit = Keyword.get(opts, :limit, 15)

    Beliefs.list_beliefs(agent, status: "active", limit: limit)
    |> Enum.map(& &1.embedding)
    |> Enum.reject(&is_nil/1)
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
