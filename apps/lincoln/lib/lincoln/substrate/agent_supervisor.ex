defmodule Lincoln.Substrate.AgentSupervisor do
  @moduledoc """
  Per-agent Supervisor that starts and manages the core cognitive
  processes: Substrate, Attention, and ThoughtSupervisor.

  Uses `:one_for_all` strategy — if any child crashes, all are restarted
  because they share state assumptions about the agent's cognitive loop.
  """

  use Supervisor

  alias Lincoln.Substrate.{Attention, Substrate, ThoughtSupervisor}

  def start_link(agent_id) when is_binary(agent_id) do
    Supervisor.start_link(__MODULE__, agent_id, name: via(agent_id))
  end

  def child_spec(agent_id) when is_binary(agent_id) do
    %{
      id: {__MODULE__, agent_id},
      start: {__MODULE__, :start_link, [agent_id]},
      type: :supervisor,
      restart: :permanent
    }
  end

  @doc "Registry via-tuple for this agent's supervisor."
  def via(agent_id) do
    {:via, Registry, {Lincoln.AgentRegistry, {agent_id, :supervisor}}}
  end

  @impl true
  def init(agent_id) do
    opts = %{agent_id: agent_id}

    children = [
      {Substrate, opts},
      {Attention, opts},
      ThoughtSupervisor.child_spec(agent_id)
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
