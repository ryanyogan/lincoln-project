defmodule Lincoln.Substrate.Driver do
  @moduledoc """
  Executes whatever the Attention process decided.

  Uses tiered inference to match compute cost to thought importance:
  - Level 0 (score < 0.3): local computation, zero HTTP calls
  - Level 1 (0.3 ≤ score < 0.7): Ollama via async Task
  - Level 2 (score ≥ 0.7): Claude via async Task

  LLM calls are async — the Driver tick never blocks waiting for a response.
  Task results arrive via handle_info and get stored as memories.

  NOTE: Token budget integration is pending. Currently defaults to :full.
  """

  use GenServer
  require Logger

  alias Lincoln.PubSubBroadcaster
  alias Lincoln.Substrate.InferenceTier

  defstruct [
    :agent_id,
    :substrate_pid,
    :current_action,
    :last_completed_action,
    action_history: [],
    tier_counts: %{local: 0, ollama: 0, claude: 0},
    pending_tasks: %{}
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
      action_history: [],
      tier_counts: %{local: 0, ollama: 0, claude: 0},
      pending_tasks: %{}
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

  def handle_cast({:execute, {belief, score}}, state) when is_map(belief) and is_number(score) do
    {:noreply, do_execute(belief, score, state)}
  end

  def handle_cast({:execute, belief}, state) when is_map(belief) do
    {:noreply, do_execute(belief, 0.5, state)}
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

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    new_state = %{state | pending_tasks: Map.delete(state.pending_tasks, ref)}

    new_state =
      case result do
        {:reflection, belief, text} ->
          store_reflection_memory(state.agent_id, belief, text)
          tier = Map.get(state.pending_tasks, ref, :ollama)
          update_tier_count(new_state, tier)

        {:skipped, _belief} ->
          update_tier_count(new_state, :local)

        {:error, _belief, reason} ->
          Logger.warning("[Driver #{state.agent_id}] LLM task failed: #{inspect(reason)}")
          new_state
      end

    {:noreply, new_state}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, %{state | pending_tasks: Map.delete(state.pending_tasks, ref)}}
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp do_execute(belief, score, state) do
    budget = :full
    tier = InferenceTier.select_tier(score, budget: budget)

    Logger.debug("[Driver #{state.agent_id}] score=#{Float.round(score / 1, 2)} tier=#{tier}")

    case tier do
      :local ->
        do_local_execution(belief, state)

      llm_tier when llm_tier in [:ollama, :claude] ->
        do_async_execution(belief, llm_tier, state)
    end
  end

  defp do_local_execution(belief, state) do
    confidence = Map.get(belief, :confidence, 0.0)
    statement = Map.get(belief, :statement, inspect(belief))

    summary =
      "Contemplating: #{statement} (confidence: #{Float.round(confidence / 1, 2)})"

    action = %{
      type: :belief_reflection,
      tier: :local,
      subject: belief,
      summary: summary,
      executed_at: DateTime.utc_now()
    }

    Logger.debug("[Driver #{state.agent_id}] Level 0: #{summary}")
    PubSubBroadcaster.broadcast_driver_action(state.agent_id, {:executed, action})

    if state.substrate_pid, do: send(state.substrate_pid, {:execution_complete, action})

    history = [action | state.action_history] |> Enum.take(20)
    tier_counts = Map.update!(state.tier_counts, :local, &(&1 + 1))

    %{
      state
      | current_action: action,
        last_completed_action: action,
        action_history: history,
        tier_counts: tier_counts
    }
  end

  defp do_async_execution(belief, tier, state) do
    statement = Map.get(belief, :statement, inspect(belief))

    action = %{
      type: :belief_reflection,
      tier: tier,
      subject: belief,
      summary: "Async #{tier} reflection on: #{statement}",
      executed_at: DateTime.utc_now()
    }

    Logger.debug("[Driver #{state.agent_id}] Level #{tier_level(tier)}: async #{tier} call")
    PubSubBroadcaster.broadcast_driver_action(state.agent_id, {:executed, action})

    if state.substrate_pid, do: send(state.substrate_pid, {:execution_complete, action})

    task =
      Task.async(fn ->
        messages = [
          %{
            role: "system",
            content: "You are reflecting on a belief. Be concise (2-3 sentences)."
          },
          %{role: "user", content: "Reflect on this belief: #{statement}"}
        ]

        case InferenceTier.execute_at_tier(tier, messages, []) do
          {:ok, :skipped} -> {:skipped, belief}
          {:ok, response} -> {:reflection, belief, response}
          {:error, reason} -> {:error, belief, reason}
        end
      end)

    history = [action | state.action_history] |> Enum.take(20)
    pending_tasks = Map.put(state.pending_tasks, task.ref, tier)

    %{
      state
      | current_action: action,
        action_history: history,
        pending_tasks: pending_tasks
    }
  end

  defp store_reflection_memory(agent_id, belief, text) do
    statement = Map.get(belief, :statement, "unknown")

    Task.start(fn ->
      agent = Lincoln.Agents.get_agent!(agent_id)

      Lincoln.Memory.create_memory(agent, %{
        content: "Reflection on belief '#{statement}': #{text}",
        memory_type: "reflection",
        importance: 5
      })
    end)
  end

  defp update_tier_count(state, tier) when tier in [:local, :ollama, :claude] do
    tier_counts = Map.update!(state.tier_counts, tier, &(&1 + 1))
    %{state | tier_counts: tier_counts}
  end

  defp tier_level(:ollama), do: 1
  defp tier_level(:claude), do: 2
end
