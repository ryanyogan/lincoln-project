defmodule Lincoln.Substrate.AgentSupervisor do
  @moduledoc """
  Per-agent Supervisor that starts and manages the five core cognitive
  processes: Substrate, Attention, Driver, Skeptic, and Resonator.

  Uses `:one_for_all` strategy — if any child crashes, all are restarted
  because they share state assumptions about the agent's cognitive loop.
  """

  use Supervisor

  alias Lincoln.Substrate.{Substrate, Attention, Driver, Skeptic, Resonator}

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
    opts = %{agent_id: agent_id, tick_interval: 5_000}
    skeptic_opts = %{agent_id: agent_id, tick_interval: 30_000}
    resonator_opts = %{agent_id: agent_id, tick_interval: 60_000}

    children = [
      {Substrate, opts},
      {Attention, opts},
      {Driver, opts},
      {Skeptic, skeptic_opts},
      {Resonator, resonator_opts}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
