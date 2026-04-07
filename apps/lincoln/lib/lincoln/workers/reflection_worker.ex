defmodule Lincoln.Workers.ReflectionWorker do
  @moduledoc """
  Oban worker for scheduled reflection cycles.

  Runs periodically to have agents reflect on their recent experiences
  and generate higher-level insights.
  """
  use Oban.Worker,
    queue: :reflection,
    max_attempts: 3,
    # Prevent duplicate jobs within 5 minutes
    unique: [period: 300]

  alias Lincoln.{Agents, Cognition}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    agent_id = args["agent_id"]

    if agent_id do
      agent = Agents.get_agent!(agent_id)
      reflect_for_agent(agent)
    else
      Agents.list_active_agents()
      |> Enum.each(&reflect_for_agent/1)
    end

    :ok
  end

  defp reflect_for_agent(agent) do
    Logger.info("Starting reflection cycle for agent: #{agent.name}")

    case Cognition.reflect(agent) do
      {:ok, result} ->
        Logger.info(
          "Reflection complete for #{agent.name}: " <>
            "#{length(result.insights)} insights from #{result.memory_count} memories"
        )

        # Touch agent activity
        Agents.touch_agent(agent)

      {:error, reason} ->
        Logger.error("Reflection failed for #{agent.name}: #{inspect(reason)}")
    end
  end

  @doc """
  Enqueues a reflection job for a specific agent.
  """
  def enqueue(agent_id) do
    %{agent_id: agent_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a reflection job for all agents.
  """
  def enqueue_all do
    %{}
    |> new()
    |> Oban.insert()
  end
end
