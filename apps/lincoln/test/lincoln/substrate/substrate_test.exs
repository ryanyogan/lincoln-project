defmodule Lincoln.Substrate.SubstrateTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Substrate

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Substrate Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "init/1" do
    test "starts with correct initial state", %{agent: agent} do
      {:ok, pid} =
        start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})
        |> then(&{:ok, &1})

      state = Substrate.get_state(pid)
      assert state.agent_id == agent.id
      assert state.agent.id == agent.id
      assert state.tick_count == 0
      assert state.pending_events == []
      assert state.activation_map == %{}
      assert state.tick_interval == 60_000
      assert %DateTime{} = state.started_at
      assert is_nil(state.last_tick_at)
    end

    test "loads current_focus from beliefs", %{agent: agent} do
      {:ok, _belief} =
        Beliefs.create_belief(agent, %{
          statement: "Focus target",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 2
        })

      {:ok, pid} =
        start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})
        |> then(&{:ok, &1})

      state = Substrate.get_state(pid)
      assert state.current_focus.statement == "Focus target"
    end

    test "registers in AgentRegistry", %{agent: agent} do
      _pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      [{pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :substrate})
      assert is_pid(pid)
    end
  end

  describe "tick loop" do
    test "tick advances tick_count", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert state.tick_count == 1
      assert %DateTime{} = state.last_tick_at
    end

    test "multiple ticks accumulate", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)
      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert state.tick_count == 2
    end

    test "tick processes pending event", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      GenServer.cast(pid, {:event, %{type: :test, content: "hello"}})
      _ = :sys.get_state(pid)
      assert Substrate.get_state(pid).pending_events |> length() == 1

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert state.pending_events == []
      assert state.tick_count == 1
    end
  end

  describe "events" do
    test "cast event adds to pending_events", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      GenServer.cast(pid, {:event, %{type: :test, content: "hello"}})
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert length(state.pending_events) == 1
      assert hd(state.pending_events).type == :test
    end

    test "send_event/2 API works", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      Substrate.send_event(pid, %{type: :external, data: "test"})
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert length(state.pending_events) == 1
    end

    test "pending_events bounded to 100", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      for i <- 1..110 do
        Substrate.send_event(pid, %{type: :flood, index: i})
      end

      _ = :sys.get_state(pid)
      state = Substrate.get_state(pid)
      assert length(state.pending_events) == 100
    end

    test "event with belief_id updates activation_map", %{agent: agent} do
      {:ok, belief} =
        Beliefs.create_belief(agent, %{
          statement: "Activated belief",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 2
        })

      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      Substrate.send_event(pid, %{type: :ref, belief_id: belief.id})
      _ = :sys.get_state(pid)

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert Map.has_key?(state.activation_map, belief.id)
    end
  end

  describe "get_state/1" do
    test "returns full state struct", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id, tick_interval: 60_000}})

      state = Substrate.get_state(pid)
      assert %Substrate{} = state
      assert state.agent_id == agent.id
      assert state.tick_count == 0
      assert is_list(state.pending_events)
      assert is_map(state.activation_map)
    end
  end
end
