defmodule Lincoln.Substrate.Substrate do
  @moduledoc """
  The core cognitive substrate — an always-running GenServer that forms
  the heart of an agent's continuous thought process.

  Each tick:
  1. Process pending external events, OR
  2. Advance focus to a different belief

  Step 1 is read-only — no DB writes, no LLM calls.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}
  alias Lincoln.Substrate.Trajectory

  @tick_interval 5_000

  defstruct [
    :agent_id,
    :agent,
    :current_focus,
    :activation_map,
    :pending_events,
    :tick_count,
    :last_tick_at,
    :tick_interval,
    :started_at
  ]

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(%{agent_id: agent_id} = opts) do
    name = {:via, Registry, {Lincoln.AgentRegistry, {agent_id, :substrate}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(%{agent_id: agent_id} = opts) do
    %{
      id: {__MODULE__, agent_id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "Returns the full state struct."
  def get_state(pid), do: GenServer.call(pid, :get_state)

  @doc "Enqueues an external event for processing on the next tick."
  def send_event(pid, event), do: GenServer.cast(pid, {:event, event})

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(%{agent_id: agent_id} = opts) do
    interval = Map.get(opts, :tick_interval, @tick_interval)

    state = %__MODULE__{
      agent_id: agent_id,
      agent: nil,
      current_focus: nil,
      activation_map: %{},
      pending_events: [],
      tick_count: 0,
      last_tick_at: nil,
      tick_interval: interval,
      started_at: DateTime.utc_now()
    }

    {:ok, state, {:continue, :load_state}}
  end

  @impl true
  def handle_continue(:load_state, state) do
    agent = Agents.get_agent!(state.agent_id)
    beliefs = Beliefs.list_beliefs(agent, limit: 10, status: "active")
    current_focus = List.first(beliefs)

    schedule_tick(state.tick_interval)

    {:noreply, %{state | agent: agent, current_focus: current_focus}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:event, event}, state) do
    pending = (state.pending_events ++ [event]) |> Enum.take(100)
    {:noreply, %{state | pending_events: pending}}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state =
      state
      |> process_next_event_or_advance_focus()
      |> Map.put(:tick_count, state.tick_count + 1)
      |> Map.put(:last_tick_at, DateTime.utc_now())

    PubSubBroadcaster.broadcast_substrate_event(
      state.agent_id,
      {:tick, new_state.tick_count, new_state.current_focus}
    )

    Task.start(fn ->
      try do
        Trajectory.record_event(state.agent_id, %{
          type: :tick,
          tick_count: new_state.tick_count,
          current_focus_id: new_state.current_focus && new_state.current_focus.id,
          pending_events_count: length(new_state.pending_events)
        })
      rescue
        e -> Logger.warning("[Substrate] Trajectory recording failed: #{Exception.message(e)}")
      end
    end)

    schedule_tick(state.tick_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    Logger.info("[Substrate #{state.agent_id}] Terminating: #{inspect(reason)}")
    :ok
  end

  # =============================================================================
  # Private — Tick Logic
  # =============================================================================

  defp process_next_event_or_advance_focus(%{pending_events: [event | rest]} = state) do
    Logger.debug("Substrate #{state.agent_id} processing event: #{inspect(event)}")

    activation_map =
      case event do
        %{belief_id: bid} when is_binary(bid) ->
          Map.put(state.activation_map, bid, DateTime.utc_now())

        _ ->
          state.activation_map
      end

    %{state | pending_events: rest, activation_map: activation_map}
  end

  defp process_next_event_or_advance_focus(state) do
    beliefs =
      Beliefs.list_beliefs(state.agent, limit: 1, status: "active")

    next_focus = List.first(beliefs)

    %{state | current_focus: next_focus}
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
