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
        start_supervised!({Substrate, %{agent_id: agent.id}})
        |> then(&{:ok, &1})

      state = Substrate.get_state(pid)
      assert state.agent_id == agent.id
      assert state.agent.id == agent.id
      assert state.pending_events == []
      assert state.activation_map == %{}
      assert %DateTime{} = state.started_at
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
        start_supervised!({Substrate, %{agent_id: agent.id}})
        |> then(&{:ok, &1})

      state = Substrate.get_state(pid)
      assert state.current_focus.statement == "Focus target"
    end

    test "registers in AgentRegistry", %{agent: agent} do
      _pid = start_supervised!({Substrate, %{agent_id: agent.id}})

      [{pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :substrate})
      assert is_pid(pid)
    end
  end

  describe "tick loop" do
    test "timeout advances tick_count", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id}})

      # Let at least one timeout fire
      Process.sleep(50)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert state.tick_count >= 1
      assert %DateTime{} = state.last_tick_at
    end

    test "timeout processes pending event immediately", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id}})

      # Send event — with timeout 0, it gets processed immediately
      GenServer.cast(pid, {:event, %{type: :test, content: "hello"}})

      # Let the timeout fire to process the event
      Process.sleep(50)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      # Events are drained immediately — pending should be empty
      assert state.pending_events == []
      assert state.tick_count >= 1
    end
  end

  describe "events" do
    test "send_event/2 API delivers events that get processed", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id}})

      Substrate.send_event(pid, %{type: :external, data: "test"})

      # With adaptive timeout, events are processed immediately
      Process.sleep(50)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      # The event was received and processed (drained)
      assert state.pending_events == []
      assert state.tick_count >= 1
    end

    test "pending_events bounded to 100", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id}})

      # Suspend the process so events accumulate without being drained
      :sys.suspend(pid)

      for i <- 1..110 do
        Substrate.send_event(pid, %{type: :flood, index: i})
      end

      # Resume and immediately check state
      :sys.resume(pid)
      state = :sys.get_state(pid)
      assert length(state.pending_events) <= 100
    end

    test "event with belief_id updates activation_map after drain", %{agent: agent} do
      {:ok, belief} =
        Beliefs.create_belief(agent, %{
          statement: "Activated belief",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 2
        })

      pid = start_supervised!({Substrate, %{agent_id: agent.id}})

      Substrate.send_event(pid, %{type: :ref, belief_id: belief.id})

      # Let the event be processed
      Process.sleep(50)
      _ = :sys.get_state(pid)

      state = Substrate.get_state(pid)
      assert Map.has_key?(state.activation_map, belief.id)
    end
  end

  describe "get_state/1" do
    test "returns full state struct", %{agent: agent} do
      pid = start_supervised!({Substrate, %{agent_id: agent.id}})

      state = Substrate.get_state(pid)
      assert %Substrate{} = state
      assert state.agent_id == agent.id
      assert is_list(state.pending_events)
      assert is_map(state.activation_map)
    end
  end
end
