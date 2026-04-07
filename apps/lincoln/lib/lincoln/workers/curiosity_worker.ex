defmodule Lincoln.Workers.CuriosityWorker do
  @moduledoc """
  Oban worker for scheduled curiosity cycles.

  Runs periodically to have agents generate new questions
  based on their experiences and interests.
  """
  use Oban.Worker,
    queue: :curiosity,
    max_attempts: 3,
    unique: [period: 300]

  alias Lincoln.{Agents, Cognition}

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    agent_id = args["agent_id"]

    if agent_id do
      agent = Agents.get_agent!(agent_id)
      curiosity_for_agent(agent)
    else
      Agents.list_active_agents()
      |> Enum.each(&curiosity_for_agent/1)
    end

    :ok
  end

  defp curiosity_for_agent(agent) do
    Logger.info("Starting curiosity cycle for agent: #{agent.name}")

    case Cognition.generate_curiosity(agent) do
      {:ok, result} ->
        Logger.info(
          "Curiosity complete for #{agent.name}: " <>
            "#{length(result.questions)} new questions"
        )

        Agents.touch_agent(agent)

      {:error, reason} ->
        Logger.error("Curiosity failed for #{agent.name}: #{inspect(reason)}")
    end
  end

  @doc """
  Enqueues a curiosity job for a specific agent.
  """
  def enqueue(agent_id) do
    %{agent_id: agent_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Enqueues a curiosity job for all agents.
  """
  def enqueue_all do
    %{}
    |> new()
    |> Oban.insert()
  end
end
