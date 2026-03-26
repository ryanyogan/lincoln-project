defmodule Lincoln.Workers.BeliefMaintenanceWorker do
  @moduledoc """
  Oban worker for belief maintenance.

  Periodically reviews beliefs for:
  1. Confidence decay on unreinforced beliefs
  2. Contradiction detection
  3. Entrenchment adjustment
  """
  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    # Once per hour max
    unique: [period: 3600]

  alias Lincoln.{Agents, Beliefs}

  require Logger

  # 1% decay per maintenance cycle for unreinforced beliefs
  @decay_rate 0.01
  # Only decay beliefs not reinforced in 30 days
  @decay_threshold_days 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    agent_id = args["agent_id"]

    cond do
      agent_id ->
        agent = Agents.get_agent!(agent_id)
        maintain_beliefs(agent)

      true ->
        Agents.list_active_agents()
        |> Enum.each(&maintain_beliefs/1)
    end

    :ok
  end

  defp maintain_beliefs(agent) do
    Logger.info("Starting belief maintenance for agent: #{agent.name}")

    beliefs = Beliefs.list_beliefs(agent)
    cutoff = DateTime.add(DateTime.utc_now(), -@decay_threshold_days * 86400, :second)

    # Decay unreinforced beliefs
    decayed_count =
      beliefs
      |> Enum.filter(fn belief ->
        is_nil(belief.last_reinforced_at) or
          DateTime.compare(belief.last_reinforced_at, cutoff) == :lt
      end)
      |> Enum.filter(fn belief ->
        # Don't decay highly entrenched or very confident beliefs
        belief.entrenchment < 5 and belief.confidence > 0.1
      end)
      |> Enum.reduce(0, fn belief, count ->
        new_confidence = max(0.1, belief.confidence - @decay_rate)

        if new_confidence != belief.confidence do
          case Beliefs.weaken_belief(belief, "Time-based decay", trigger_type: "decay") do
            {:ok, _} -> count + 1
            {:error, _} -> count
          end
        else
          count
        end
      end)

    Logger.info(
      "Belief maintenance complete for #{agent.name}: " <>
        "#{decayed_count} beliefs decayed"
    )
  end

  @doc """
  Enqueues maintenance for a specific agent.
  """
  def enqueue(agent_id) do
    %{agent_id: agent_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues maintenance for all agents.
  """
  def enqueue_all do
    %{}
    |> new()
    |> Oban.insert()
  end
end
