defmodule Lincoln.Substrate.ThoughtSupervisor do
  @moduledoc """
  Per-agent DynamicSupervisor that manages all running Thought processes.
  Each substrate tick may spawn a Thought here. Thoughts are short-lived:
  they spawn, execute, and terminate normally when complete.
  """

  use DynamicSupervisor

  def start_link(agent_id) when is_binary(agent_id) do
    DynamicSupervisor.start_link(__MODULE__, agent_id, name: via(agent_id))
  end

  def child_spec(agent_id) when is_binary(agent_id) do
    %{
      id: {__MODULE__, agent_id},
      start: {__MODULE__, :start_link, [agent_id]},
      type: :supervisor,
      restart: :permanent
    }
  end

  def via(agent_id) do
    {:via, Registry, {Lincoln.AgentRegistry, {agent_id, :thought_supervisor}}}
  end

  @doc "Spawn a Thought process under this supervisor."
  def spawn_thought(agent_id, opts) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, :thought_supervisor}) do
      [{sup_pid, _}] ->
        DynamicSupervisor.start_child(sup_pid, {Lincoln.Substrate.Thought, opts})

      [] ->
        {:error, :thought_supervisor_not_running}
    end
  end

  @doc "List all currently running thoughts for this agent."
  def list_children(agent_id) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, :thought_supervisor}) do
      [{sup_pid, _}] ->
        DynamicSupervisor.which_children(sup_pid)

      [] ->
        []
    end
  end

  @impl true
  def init(_agent_id) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
