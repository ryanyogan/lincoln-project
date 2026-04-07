defmodule Lincoln.Substrate.Driver do
  @moduledoc """
  Executes whatever the Attention process decided.

  In Step 1, "execution" is minimal: log the action and broadcast via PubSub.
  No LLM calls, no blocking — fire-and-forget.

  After execution, notifies the Substrate process (if configured) with
  `{:execution_complete, action}`.
  """

  use GenServer
  require Logger

  alias Lincoln.PubSubBroadcaster

  defstruct [
    :agent_id,
    :substrate_pid,
    :current_action,
    :last_completed_action,
    action_history: []
  ]

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(%{agent_id: agent_id} = opts) do
    name = {:via, Registry, {Lincoln.AgentRegistry, {agent_id, :driver}}}
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

  @doc "Cast a thought for execution (fire-and-forget)."
  def execute(pid, thought), do: GenServer.cast(pid, {:execute, thought})

  @doc "Cast an external event for processing."
  def execute_event(pid, event), do: GenServer.cast(pid, {:execute_event, event})

  @doc "Returns the current driver state."
  def get_state(pid), do: GenServer.call(pid, :get_state)

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(%{agent_id: agent_id} = opts) do
    state = %__MODULE__{
      agent_id: agent_id,
      substrate_pid: Map.get(opts, :substrate_pid),
      current_action: nil,
      last_completed_action: nil,
      action_history: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:execute, nil}, state) do
    Logger.debug("[Driver #{state.agent_id}] No thought to execute (nil)")
    {:noreply, %{state | current_action: nil}}
  end

  def handle_cast({:execute, thought}, state) when is_map(thought) do
    action = %{
      type: :belief_reflection,
      subject: thought,
      executed_at: DateTime.utc_now()
    }

    Logger.debug("[Driver #{state.agent_id}] Executing: #{inspect(thought)}")
    PubSubBroadcaster.broadcast_driver_action(state.agent_id, {:executed, action})

    if state.substrate_pid do
      send(state.substrate_pid, {:execution_complete, action})
    end

    history = [action | state.action_history] |> Enum.take(20)

    {:noreply,
     %{state | current_action: action, last_completed_action: action, action_history: history}}
  end

  @impl true
  def handle_cast({:execute_event, event}, state) do
    action = %{
      type: :external_event,
      event: event,
      executed_at: DateTime.utc_now()
    }

    Logger.debug("[Driver #{state.agent_id}] Processing external event: #{inspect(event)}")
    PubSubBroadcaster.broadcast_driver_action(state.agent_id, {:executed, action})

    if state.substrate_pid do
      send(state.substrate_pid, {:execution_complete, action})
    end

    history = [action | state.action_history] |> Enum.take(20)

    {:noreply,
     %{state | current_action: action, last_completed_action: action, action_history: history}}
  end
end
