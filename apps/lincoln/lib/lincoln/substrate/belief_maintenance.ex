defmodule Lincoln.Substrate.BeliefMaintenance do
  @moduledoc """
  Substrate-native belief maintenance — confidence decay for unreinforced beliefs.

  Extracted from BeliefMaintenanceWorker to run inside the substrate tick loop
  rather than as an Oban cron job.
  """

  alias Lincoln.{Agents, Beliefs}
  require Logger

  @decay_threshold_days 30

  @doc """
  Decay confidence on beliefs that haven't been reinforced in 30+ days.
  Only affects beliefs with confidence > 0.1 and entrenchment < 5.
  """
  def decay_unreinforced(agent_id) do
    agent = Agents.get_agent!(agent_id)
    beliefs = Beliefs.list_beliefs(agent)
    cutoff = DateTime.add(DateTime.utc_now(), -@decay_threshold_days * 86_400, :second)

    decayed_count =
      beliefs
      |> Enum.filter(fn belief ->
        (is_nil(belief.last_reinforced_at) or
           DateTime.compare(belief.last_reinforced_at, cutoff) == :lt) and
          belief.entrenchment < 5 and belief.confidence > 0.1
      end)
      |> Enum.reduce(0, fn belief, count ->
        case Beliefs.weaken_belief(belief, "Time-based decay", trigger_type: "decay") do
          {:ok, _} -> count + 1
          {:error, _} -> count
        end
      end)

    if decayed_count > 0 do
      Logger.info("[BeliefMaintenance #{agent_id}] Decayed #{decayed_count} unreinforced beliefs")
    end

    decayed_count
  end
end
