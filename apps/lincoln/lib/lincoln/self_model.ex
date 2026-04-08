defmodule Lincoln.SelfModel do
  @moduledoc """
  What Lincoln knows about itself — capabilities, limitations, learning trajectory.
  Single row per agent, updated every 50 substrate ticks from trajectory data.
  """

  import Ecto.Query
  require Logger

  alias Lincoln.Repo
  alias Lincoln.SelfModel.AgentSelfModel
  alias Lincoln.Substrate.SubstrateEvent

  def get_or_create(agent_id) when is_binary(agent_id) do
    case Repo.get_by(AgentSelfModel, agent_id: agent_id) do
      nil ->
        %AgentSelfModel{}
        |> AgentSelfModel.changeset(%{agent_id: agent_id})
        |> Repo.insert()

      model ->
        {:ok, model}
    end
  end

  def get(agent_id), do: Repo.get_by(AgentSelfModel, agent_id: agent_id)

  def update_from_trajectory(agent_id) when is_binary(agent_id) do
    with {:ok, model} <- get_or_create(agent_id) do
      events = SubstrateEvent |> where([e], e.agent_id == ^agent_id) |> Repo.all()

      thought_complete = Enum.count(events, fn e -> e.event_type == "thought_completed" end)
      thought_failed = Enum.count(events, fn e -> e.event_type == "thought_failed" end)
      tick_events = Enum.filter(events, fn e -> e.event_type == "tick" end)

      tier_counts = count_tiers(tick_events)
      narrative_count = Lincoln.Narratives.count_reflections(agent_id)

      model
      |> AgentSelfModel.changeset(%{
        total_thoughts: thought_complete + thought_failed,
        completed_thoughts: thought_complete,
        failed_thoughts: thought_failed,
        local_tier_count: tier_counts.local,
        ollama_tier_count: tier_counts.ollama,
        claude_tier_count: tier_counts.claude,
        total_ticks: length(tick_events),
        narrative_count: narrative_count,
        last_updated_at: DateTime.utc_now()
      })
      |> Repo.update()
    end
  rescue
    e -> Logger.warning("[SelfModel] Update failed: #{Exception.message(e)}")
  end

  def to_summary_string(nil), do: "No self-model yet."

  def to_summary_string(%AgentSelfModel{} = m) do
    success_rate =
      if m.total_thoughts > 0,
        do: round(m.completed_thoughts / m.total_thoughts * 100),
        else: 0

    "#{m.total_thoughts} thoughts (#{success_rate}% success) · " <>
      "#{m.total_ticks} ticks · #{m.narrative_count} reflections"
  end

  defp count_tiers(tick_events) do
    Enum.reduce(tick_events, %{local: 0, ollama: 0, claude: 0}, fn e, acc ->
      tier = get_in(e.event_data || %{}, ["tier"]) || ""

      case to_string(tier) do
        "local" -> Map.update!(acc, :local, &(&1 + 1))
        "ollama" -> Map.update!(acc, :ollama, &(&1 + 1))
        "claude" -> Map.update!(acc, :claude, &(&1 + 1))
        _ -> acc
      end
    end)
  end
end
