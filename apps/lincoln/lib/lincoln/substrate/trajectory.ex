defmodule Lincoln.Substrate.Trajectory do
  @moduledoc """
  Records and queries agent cognitive trajectories for divergence analysis.

  A "trajectory" is the sequence of actions an agent took over time,
  including what it focused on, which tier was used, and what events were processed.
  """

  import Ecto.Query
  alias Lincoln.Repo
  alias Lincoln.Substrate.SubstrateEvent

  @doc "Record a substrate event in the trajectory log."
  def record_event(agent_id, event_data) when is_map(event_data) do
    %SubstrateEvent{}
    |> SubstrateEvent.changeset(%{
      agent_id: agent_id,
      event_type: to_string(Map.get(event_data, :type, :unknown)),
      event_data: event_data,
      tick_number: Map.get(event_data, :tick_count, 0),
      attention_score: Map.get(event_data, :attention_score),
      inference_tier: to_string(Map.get(event_data, :tier, :local))
    })
    |> Repo.insert()
  end

  @doc "Compare trajectories of two agents side-by-side."
  def compare(agent_id_1, agent_id_2, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    events_1 = get_events(agent_id_1, limit)
    events_2 = get_events(agent_id_2, limit)

    %{
      agent_1: %{agent_id: agent_id_1, events: events_1},
      agent_2: %{agent_id: agent_id_2, events: events_2}
    }
  end

  @doc "Get trajectory summary for an agent."
  def summary(agent_id, opts \\ []) do
    hours = Keyword.get(opts, :hours, 1)
    since = DateTime.add(DateTime.utc_now(), -hours, :hour)

    events =
      SubstrateEvent
      |> where([e], e.agent_id == ^agent_id)
      |> where([e], e.inserted_at >= ^since)
      |> Repo.all()

    tier_distribution =
      events
      |> Enum.group_by(& &1.inference_tier)
      |> Map.new(fn {tier, evs} -> {tier, length(evs)} end)

    %{
      agent_id: agent_id,
      total_events: length(events),
      tier_distribution: tier_distribution,
      time_range: %{since: since, now: DateTime.utc_now()}
    }
  end

  defp get_events(agent_id, limit) do
    SubstrateEvent
    |> where([e], e.agent_id == ^agent_id)
    |> order_by([e], desc: e.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
