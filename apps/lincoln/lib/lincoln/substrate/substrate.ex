defmodule Lincoln.Substrate.Substrate do
  @moduledoc """
  The core cognitive substrate — an always-running GenServer.

  Every tick: drain events → ask Attention what to think about → ask Driver to execute → record trajectory.
  The substrate never idles. Even with no events, Attention still scores and Driver still executes.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}
  alias Lincoln.Substrate.{Attention, Thought, ThoughtSupervisor, Trajectory}

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
    :started_at,
    :last_attention_score,
    :last_tier
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
      started_at: DateTime.utc_now(),
      last_attention_score: nil,
      last_tier: nil
    }

    {:ok, state, {:continue, :load_state}}
  end

  @impl true
  def handle_continue(:load_state, state) do
    agent = Agents.get_agent!(state.agent_id)
    beliefs = Beliefs.list_beliefs(agent, limit: 10, status: "active")
    current_focus = List.first(beliefs)

    Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.thought_topic(state.agent_id))
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
    state_after_events = drain_pending_events(state)
    {chosen_belief, attention_score} = consult_attention(state_after_events)
    tier = spawn_thought(state_after_events, chosen_belief, attention_score)

    new_state = %{
      state_after_events
      | current_focus: chosen_belief,
        tick_count: state.tick_count + 1,
        last_tick_at: DateTime.utc_now(),
        last_attention_score: attention_score,
        last_tier: tier
    }

    PubSubBroadcaster.broadcast_substrate_event(
      state.agent_id,
      {:tick, new_state.tick_count, new_state.current_focus}
    )

    record_trajectory(state.agent_id, new_state, chosen_belief, attention_score, tier)
    schedule_tick(state.tick_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:execution_complete, _action}, state), do: {:noreply, state}

  @impl true
  def handle_info({:thought_completed, thought_id, result}, state) do
    Logger.debug(
      "[Substrate #{state.agent_id}] Thought #{thought_id} completed: #{String.slice(to_string(result), 0, 80)}"
    )

    activation_map =
      if state.current_focus do
        Map.put(state.activation_map, state.current_focus.id, DateTime.utc_now())
      else
        state.activation_map
      end

    Task.start(fn ->
      try do
        Trajectory.record_event(state.agent_id, %{
          type: :thought_completed,
          thought_id: thought_id,
          belief_id: state.current_focus && Map.get(state.current_focus, :id),
          belief_statement: state.current_focus && Map.get(state.current_focus, :statement),
          result_summary: String.slice(to_string(result), 0, 200),
          tick_count: state.tick_count
        })
      rescue
        e -> Logger.warning("[Substrate] Thought trajectory failed: #{Exception.message(e)}")
      end
    end)

    {:noreply, %{state | activation_map: activation_map}}
  end

  @impl true
  def handle_info({:thought_failed, thought_id, reason}, state) do
    Logger.warning(
      "[Substrate #{state.agent_id}] Thought #{thought_id} failed: #{inspect(reason)}"
    )

    Task.start(fn ->
      try do
        Trajectory.record_event(state.agent_id, %{
          type: :thought_failed,
          thought_id: thought_id,
          reason: inspect(reason),
          tick_count: state.tick_count
        })
      rescue
        e ->
          Logger.warning("[Substrate] Thought failure trajectory failed: #{Exception.message(e)}")
      end
    end)

    {:noreply, state}
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

  defp drain_pending_events(%{pending_events: []} = state), do: state

  defp drain_pending_events(%{pending_events: events} = state) do
    activation_map =
      Enum.reduce(events, state.activation_map, fn event, acc ->
        case event do
          %{belief_id: bid} when is_binary(bid) -> Map.put(acc, bid, DateTime.utc_now())
          _ -> acc
        end
      end)

    Logger.debug("[Substrate #{state.agent_id}] Drained #{length(events)} events")
    %{state | pending_events: [], activation_map: activation_map}
  end

  defp consult_attention(state) do
    case lookup_process(state.agent_id, :attention) do
      {:ok, pid} ->
        case Attention.next_thought(pid) do
          {:ok, belief, score} -> {belief, score}
          {:ok, nil} -> {nil, nil}
        end

      {:error, :not_running} ->
        belief =
          if state.agent,
            do: Beliefs.list_beliefs(state.agent, limit: 1, status: "active") |> List.first()

        {belief, nil}
    end
  end

  defp spawn_thought(_state, nil, _score), do: :no_belief

  defp spawn_thought(state, belief, score) do
    interrupt_threshold = get_interrupt_threshold(state)

    case ThoughtSupervisor.list_children(state.agent_id) do
      [] ->
        # No thought running — spawn freely
        do_spawn_thought(state, belief, score)

      [{_id, pid, _type, _modules} | _rest] when is_pid(pid) ->
        # A thought is running — check interrupt_threshold
        if score >= interrupt_threshold do
          Logger.debug(
            "[Substrate #{state.agent_id}] Interrupting thought " <>
              "(score #{Float.round(score, 2)} >= threshold #{Float.round(interrupt_threshold, 2)})"
          )

          Thought.interrupt(pid)
          do_spawn_thought(state, belief, score)
        else
          Logger.debug(
            "[Substrate #{state.agent_id}] Thought running, skipping spawn " <>
              "(score #{Float.round(score, 2)} < threshold #{Float.round(interrupt_threshold, 2)})"
          )

          :thought_running
        end

      _ ->
        do_spawn_thought(state, belief, score)
    end
  end

  defp do_spawn_thought(state, belief, score) do
    thought_opts = %{
      agent_id: state.agent_id,
      belief: belief,
      attention_score: score || 0.0
    }

    case ThoughtSupervisor.spawn_thought(state.agent_id, thought_opts) do
      {:ok, _pid} ->
        Lincoln.Substrate.InferenceTier.select_tier(score || 0.0)

      {:error, reason} ->
        Logger.debug("[Substrate #{state.agent_id}] Could not spawn thought: #{inspect(reason)}")
        nil
    end
  end

  defp get_interrupt_threshold(state) do
    params = state.agent && state.agent.attention_params

    raw =
      (params && Map.get(params, "interrupt_threshold")) ||
        (params && Map.get(params, :interrupt_threshold)) ||
        0.7

    case raw do
      f when is_float(f) -> f
      i when is_integer(i) -> i * 1.0
      _ -> 0.7
    end
  end

  defp record_trajectory(agent_id, state, belief, score, tier) do
    Task.start(fn ->
      try do
        Trajectory.record_event(agent_id, %{
          type: :tick,
          tick_count: state.tick_count,
          current_focus_id: belief && Map.get(belief, :id),
          current_focus_statement: belief && Map.get(belief, :statement),
          attention_score: score,
          tier: tier,
          pending_events_count: length(state.pending_events)
        })
      rescue
        e -> Logger.warning("[Substrate] Trajectory recording failed: #{Exception.message(e)}")
      end
    end)
  end

  defp lookup_process(agent_id, type) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, type}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_running}
    end
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
