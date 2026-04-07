defmodule Lincoln.Substrate do
  @moduledoc """
  Public API for managing agent cognitive substrate processes.

  Each agent runs five processes under a per-agent supervisor:
  - **Substrate** — the core tick loop and event processing
  - **Attention** — decides what to think about next
  - **Driver** — executes decided actions
  - **Skeptic** — questions and validates beliefs
  - **Resonator** — reflects on experiences and extracts insights
  """

  alias Lincoln.Agents
  alias Lincoln.Substrate.{AgentSupervisor, Substrate}

  @doc """
  Start all substrate processes for an agent.

  Validates the agent exists in the database and is not already running.
  Returns `{:ok, pid}` on success.
  """
  def start_agent(agent_id) when is_binary(agent_id) do
    case Agents.get_agent(agent_id) do
      nil ->
        {:error, :agent_not_found}

      _agent ->
        case Registry.lookup(Lincoln.AgentRegistry, {agent_id, :supervisor}) do
          [{_pid, _}] ->
            {:error, :already_started}

          [] ->
            DynamicSupervisor.start_child(
              Lincoln.AgentSupervisor,
              AgentSupervisor.child_spec(agent_id)
            )
        end
    end
  end

  @doc """
  Stop all substrate processes for an agent.

  Returns `:ok` on success or `{:error, :not_running}` if agent is not running.
  """
  def stop_agent(agent_id) when is_binary(agent_id) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, :supervisor}) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Lincoln.AgentSupervisor, pid)

      [] ->
        {:error, :not_running}
    end
  end

  @doc """
  Get the current cognitive state of an agent's substrate.

  Returns `{:ok, state}` or `{:error, :not_running}`.
  """
  def get_agent_state(agent_id) when is_binary(agent_id) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, :substrate}) do
      [{pid, _}] -> {:ok, Substrate.get_state(pid)}
      [] -> {:error, :not_running}
    end
  end

  @doc """
  Send an external event to an agent's substrate.

  Returns `:ok` or `{:error, :not_running}`.
  """
  def send_event(agent_id, event) when is_binary(agent_id) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, :substrate}) do
      [{pid, _}] ->
        Substrate.send_event(pid, event)
        :ok

      [] ->
        {:error, :not_running}
    end
  end

  @doc """
  List all currently running agent IDs.
  """
  def list_running_agents do
    Lincoln.AgentRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.filter(fn
      {_agent_id, :supervisor} -> true
      _ -> false
    end)
    |> Enum.map(fn {agent_id, :supervisor} -> agent_id end)
  end

  @doc """
  Get a specific process PID for an agent.

  `type` must be one of `:substrate`, `:attention`, `:driver`, `:skeptic`, or `:resonator`.
  """
  def get_process(agent_id, type)
      when type in [:substrate, :attention, :driver, :skeptic, :resonator] do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, type}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_running}
    end
  end
end
