defmodule Lincoln.Substrate.Substrate do
  @moduledoc """
  The core cognitive substrate — an always-running GenServer.

  Every tick: drain events → consult Attention → spawn Thought → record trajectory.
  The substrate never idles. Even with no events, Attention still scores and
  idle ticks produce local contemplation.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}

  alias Lincoln.Substrate.{
    Attention,
    BeliefMaintenance,
    InferenceTier,
    Resonator,
    Skeptic,
    Thought,
    ThoughtSupervisor,
    Trajectory
  }

  @default_timeout 5_000
  @narrative_interval 200
  @self_model_interval 50
  @belief_maintenance_interval 1000
  @skeptic_interval 6
  @resonator_interval 12

  defstruct [
    :agent_id,
    :agent,
    :current_focus,
    :activation_map,
    :pending_events,
    :tick_count,
    :last_tick_at,
    :started_at,
    :last_attention_score,
    :last_tier,
    idle_streak: 0
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
  def init(%{agent_id: agent_id} = _opts) do
    state = %__MODULE__{
      agent_id: agent_id,
      agent: nil,
      current_focus: nil,
      activation_map: %{},
      pending_events: [],
      tick_count: 0,
      last_tick_at: nil,
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
    Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.skeptic_topic(state.agent_id))
    Phoenix.PubSub.subscribe(Lincoln.PubSub, PubSubBroadcaster.resonator_topic(state.agent_id))

    # Zero timeout triggers the first tick immediately
    {:noreply, %{state | agent: agent, current_focus: current_focus}, 0}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:event, event}, state) do
    pending = (state.pending_events ++ [event]) |> Enum.take(100)
    # Zero timeout — process the event on the very next iteration
    {:noreply, %{state | pending_events: pending}, 0}
  end

  @impl true
  def handle_info(:timeout, state) do
    new_state =
      if state.pending_events != [] or not has_running_thought?(state) do
        handle_active_tick(state)
      else
        handle_idle_tick(state)
      end

    run_periodic_tasks(new_state)
    {:noreply, new_state, next_timeout(new_state)}
  end

  @impl true
  def handle_info({:execution_complete, _action}, state), do: {:noreply, state}

  @impl true
  def handle_info({:thought_completed, thought_id, result}, state) do
    Logger.debug(
      "[Substrate #{state.agent_id}] Thought #{thought_id} completed: #{String.slice(to_string(result), 0, 80)}"
    )

    activation_map = activate_current_focus(state)

    event_data = %{
      type: :thought_completed,
      thought_id: thought_id,
      belief_id: state.current_focus && Map.get(state.current_focus, :id),
      belief_statement: state.current_focus && Map.get(state.current_focus, :statement),
      result_summary: String.slice(to_string(result), 0, 200),
      tick_count: state.tick_count
    }

    run_background_task(fn -> Trajectory.record_event(state.agent_id, event_data) end,
      label: "thought trajectory"
    )

    {:noreply, %{state | activation_map: activation_map}, 0}
  end

  @impl true
  def handle_info({:thought_failed, thought_id, reason}, state) do
    Logger.warning(
      "[Substrate #{state.agent_id}] Thought #{thought_id} failed: #{inspect(reason)}"
    )

    event_data = %{
      type: :thought_failed,
      thought_id: thought_id,
      reason: inspect(reason),
      tick_count: state.tick_count
    }

    run_background_task(fn -> Trajectory.record_event(state.agent_id, event_data) end,
      label: "thought failure trajectory"
    )

    {:noreply, state, 0}
  end

  # Skeptic detected a contradiction — queue it as an event for processing
  def handle_info({:contradiction_detected, relationship, belief_a, belief_b}, state) do
    event = %{
      type: :contradiction,
      belief_a_id: belief_a.id,
      belief_b_id: belief_b.id,
      relationship_id: relationship.id
    }

    pending = (state.pending_events ++ [event]) |> Enum.take(100)
    {:noreply, %{state | pending_events: pending}, 0}
  end

  # Resonator detected a cascade — queue it as an event for processing
  def handle_info({:cascade_detected, cascade_info}, state) do
    event = %{
      type: :cascade,
      belief_ids: cascade_info.belief_ids,
      cascade_score: cascade_info.cascade_score
    }

    pending = (state.pending_events ++ [event]) |> Enum.take(100)
    {:noreply, %{state | pending_events: pending}, 0}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state, next_timeout(state)}

  @impl true
  def terminate(reason, state) do
    Logger.info("[Substrate #{state.agent_id}] Terminating: #{inspect(reason)}")
    :ok
  end

  # =============================================================================
  # Private — Tick Logic
  # =============================================================================

  defp has_running_thought?(state) do
    ThoughtSupervisor.list_children(state.agent_id) != []
  end

  defp run_periodic_tasks(state) do
    tick = state.tick_count
    if tick == 0, do: :noop

    if tick > 0 do
      if rem(tick, @narrative_interval) == 0, do: spawn_narrative_thought(state)
      if rem(tick, @self_model_interval) == 0, do: update_self_model(state.agent_id)

      if rem(tick, @skeptic_interval) == 0 do
        run_background_task(fn -> Skeptic.detect_contradictions(state.agent) end,
          label: "skeptic"
        )
      end

      if rem(tick, @resonator_interval) == 0 do
        run_background_task(fn -> Resonator.detect_cascades(state.agent) end,
          label: "resonator"
        )
      end

      if rem(tick, @belief_maintenance_interval) == 0 do
        run_background_task(fn -> BeliefMaintenance.decay_unreinforced(state.agent_id) end,
          label: "belief maintenance"
        )
      end
    end
  end

  defp run_background_task(fun, opts) do
    label = Keyword.get(opts, :label, "background task")

    Task.start(fn ->
      try do
        fun.()
      rescue
        e -> Logger.debug("[Substrate] #{label} failed: #{Exception.message(e)}")
      end
    end)
  end

  defp handle_active_tick(state) do
    state_after_events = drain_pending_events(state)
    {chosen_belief, attention_score, scoring_detail} = consult_attention(state_after_events)
    tier = spawn_thought(state_after_events, chosen_belief, attention_score)

    new_state = %{
      state_after_events
      | current_focus: chosen_belief,
        tick_count: state.tick_count + 1,
        last_tick_at: DateTime.utc_now(),
        last_attention_score: attention_score,
        last_tier: tier,
        idle_streak: 0
    }

    PubSubBroadcaster.broadcast_substrate_event(
      state.agent_id,
      {:tick, new_state.tick_count, new_state.current_focus, scoring_detail}
    )

    record_trajectory(
      state.agent_id,
      new_state,
      chosen_belief,
      attention_score,
      tier,
      scoring_detail
    )

    new_state
  end

  defp handle_idle_tick(state) do
    {idle_belief, idle_score, idle_detail} = consult_attention_idle(state)

    new_state = %{
      state
      | current_focus: idle_belief || state.current_focus,
        tick_count: state.tick_count + 1,
        last_tick_at: DateTime.utc_now(),
        last_attention_score: idle_score,
        idle_streak: state.idle_streak + 1
    }

    PubSubBroadcaster.broadcast_substrate_event(
      state.agent_id,
      {:idle_tick, new_state.tick_count, new_state.idle_streak, idle_belief}
    )

    record_idle_trajectory(state.agent_id, new_state, idle_belief, idle_score, idle_detail)
    new_state
  end

  defp drain_pending_events(%{pending_events: []} = state), do: state

  defp drain_pending_events(%{pending_events: events} = state) do
    now = DateTime.utc_now()

    {reactive_events, regular_events} =
      Enum.split_with(events, fn
        %{type: type} when type in [:contradiction, :cascade] -> true
        _ -> false
      end)

    activation_map =
      regular_events
      |> Enum.flat_map(&extract_belief_ids/1)
      |> Enum.reduce(state.activation_map, fn bid, acc -> Map.put(acc, bid, now) end)

    # Spawn reactive thoughts for contradiction/cascade signals
    Enum.each(reactive_events, fn event ->
      spawn_reactive_thought(state, event)
    end)

    Logger.debug("[Substrate #{state.agent_id}] Drained #{length(events)} events")
    %{state | pending_events: [], activation_map: activation_map}
  end

  defp activate_current_focus(%{current_focus: %{id: id}} = state) when is_binary(id) do
    Map.put(state.activation_map, id, DateTime.utc_now())
  end

  defp activate_current_focus(state), do: state.activation_map

  defp spawn_reactive_thought(state, %{type: source} = signal) do
    # Create a synthetic impulse belief that routes to the right handler
    impulse_id = "impulse:#{source}"

    thought_opts = %{
      agent_id: state.agent_id,
      belief: %{
        id: impulse_id,
        statement: "Reactive: #{source}",
        confidence: 0.9,
        source_type: "introspection"
      },
      attention_score: 0.9,
      force_tier: :local,
      reactive_context: signal
    }

    case ThoughtSupervisor.spawn_thought(state.agent_id, thought_opts) do
      {:ok, _pid} ->
        Logger.info("[Substrate #{state.agent_id}] Spawned reactive thought: #{source}")

      {:error, reason} ->
        Logger.debug(
          "[Substrate #{state.agent_id}] Could not spawn reactive thought: #{inspect(reason)}"
        )
    end
  end

  defp extract_belief_ids(%{belief_id: bid}) when is_binary(bid), do: [bid]

  defp extract_belief_ids(%{type: :conversation, belief_ids: ids}) when is_list(ids) do
    Enum.filter(ids, &is_binary/1)
  end

  defp extract_belief_ids(_), do: []

  defp consult_attention(state) do
    case lookup_process(state.agent_id, :attention) do
      {:ok, pid} ->
        case Attention.next_thought(pid) do
          {:ok, belief, score, scoring_detail} -> {belief, score, scoring_detail}
          {:ok, nil} -> {nil, nil, nil}
        end

      {:error, :not_running} ->
        belief =
          if state.agent,
            do: Beliefs.list_beliefs(state.agent, limit: 1, status: "active") |> List.first()

        {belief, nil, nil}
    end
  end

  defp consult_attention_idle(state) do
    case lookup_process(state.agent_id, :attention) do
      {:ok, pid} ->
        case Attention.idle_score(pid) do
          {:ok, belief, score, scoring_detail} -> {belief, score, scoring_detail}
          {:ok, nil} -> {nil, nil, nil}
        end

      {:error, :not_running} ->
        {nil, nil, nil}
    end
  end

  defp record_idle_trajectory(agent_id, state, belief, score, scoring_detail) do
    event_data = %{
      type: :idle_tick,
      tick_count: state.tick_count,
      idle_streak: state.idle_streak,
      current_focus_id: belief && Map.get(belief, :id),
      current_focus_statement: belief && Map.get(belief, :statement),
      attention_score: score,
      tier: :local,
      pending_events_count: 0,
      scoring: scoring_detail
    }

    run_background_task(fn -> Trajectory.record_event(agent_id, event_data) end,
      label: "idle trajectory recording"
    )
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
        InferenceTier.select_tier(score || 0.0)

      {:error, reason} ->
        Logger.debug("[Substrate #{state.agent_id}] Could not spawn thought: #{inspect(reason)}")
        nil
    end
  end

  defp get_interrupt_threshold(state) do
    agent =
      try do
        Agents.get_agent!(state.agent_id)
      rescue
        _ -> state.agent
      end

    parse_interrupt_threshold(agent && agent.attention_params)
  end

  defp parse_interrupt_threshold(nil), do: 0.7

  defp parse_interrupt_threshold(params) do
    raw =
      Map.get(params, "interrupt_threshold") ||
        Map.get(params, :interrupt_threshold) ||
        0.7

    case raw do
      f when is_float(f) -> f
      i when is_integer(i) -> i * 1.0
      _ -> 0.7
    end
  end

  defp record_trajectory(agent_id, state, belief, score, tier, scoring_detail) do
    event_data = %{
      type: :tick,
      tick_count: state.tick_count,
      current_focus_id: belief && Map.get(belief, :id),
      current_focus_statement: belief && Map.get(belief, :statement),
      attention_score: score,
      tier: tier,
      pending_events_count: length(state.pending_events),
      scoring: scoring_detail
    }

    run_background_task(fn -> Trajectory.record_event(agent_id, event_data) end,
      label: "trajectory recording"
    )
  end

  defp lookup_process(agent_id, type) do
    case Registry.lookup(Lincoln.AgentRegistry, {agent_id, type}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_running}
    end
  end

  defp spawn_narrative_thought(state) do
    narrative_belief = %{
      id: nil,
      statement: "Reflect on what I have been thinking about and learning recently",
      confidence: 1.0,
      source_type: "introspection"
    }

    thought_opts = %{
      agent_id: state.agent_id,
      belief: narrative_belief,
      attention_score: 0.9,
      is_narrative: true,
      narrative_tick: state.tick_count
    }

    case ThoughtSupervisor.spawn_thought(state.agent_id, thought_opts) do
      {:ok, _pid} ->
        Logger.info(
          "[Substrate #{state.agent_id}] Narrative thought spawned at tick #{state.tick_count}"
        )

      {:error, reason} ->
        Logger.debug("[Substrate #{state.agent_id}] Narrative thought failed: #{inspect(reason)}")
    end
  end

  defp update_self_model(agent_id) do
    run_background_task(fn -> Lincoln.SelfModel.update_from_trajectory(agent_id) end,
      label: "self model update"
    )
  end

  defp next_timeout(state) do
    cond do
      state.pending_events != [] -> 0
      state.idle_streak == 0 -> 1_000
      state.idle_streak < 10 -> 3_000
      true -> @default_timeout
    end
  end
end
