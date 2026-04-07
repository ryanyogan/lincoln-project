defmodule Lincoln.Substrate.DriverTest do
  use Lincoln.DataCase

  alias Lincoln.Substrate.Driver

  setup do
    {:ok, agent} = Lincoln.Agents.create_agent(%{name: "Driver Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "execute/2" do
    test "executes a thought and updates current_action", %{agent: agent} do
      pid = start_supervised!({Driver, %{agent_id: agent.id}})
      thought = %{id: "belief-1", statement: "Test belief"}

      Driver.execute(pid, thought)
      _ = :sys.get_state(pid)

      state = Driver.get_state(pid)
      assert state.current_action != nil
      assert state.current_action.type == :belief_reflection
    end

    test "adds to action_history", %{agent: agent} do
      pid = start_supervised!({Driver, %{agent_id: agent.id}})

      Driver.execute(pid, %{id: "b1", statement: "First"})
      Driver.execute(pid, %{id: "b2", statement: "Second"})
      _ = :sys.get_state(pid)

      state = Driver.get_state(pid)
      assert length(state.action_history) == 2
    end

    test "handles nil thought gracefully", %{agent: agent} do
      pid = start_supervised!({Driver, %{agent_id: agent.id}})
      Driver.execute(pid, nil)
      _ = :sys.get_state(pid)
      state = Driver.get_state(pid)
      assert state.current_action == nil
    end

    test "notifies substrate_pid on completion", %{agent: agent} do
      test_pid = self()
      pid = start_supervised!({Driver, %{agent_id: agent.id, substrate_pid: test_pid}})
      Driver.execute(pid, %{id: "b1", statement: "Test"})
      assert_receive {:execution_complete, _action}, 500
    end

    test "bounds action_history to 20 entries", %{agent: agent} do
      pid = start_supervised!({Driver, %{agent_id: agent.id}})

      for i <- 1..25 do
        Driver.execute(pid, %{id: "b#{i}", statement: "Belief #{i}"})
      end

      _ = :sys.get_state(pid)
      state = Driver.get_state(pid)
      assert length(state.action_history) == 20
    end
  end

  describe "execute_event/2" do
    test "processes external event and updates state", %{agent: agent} do
      pid = start_supervised!({Driver, %{agent_id: agent.id}})
      event = %{type: :conversation, content: "hello"}

      Driver.execute_event(pid, event)
      _ = :sys.get_state(pid)

      state = Driver.get_state(pid)
      assert state.current_action.type == :external_event
      assert state.current_action.event == event
    end

    test "notifies substrate_pid on event completion", %{agent: agent} do
      test_pid = self()
      pid = start_supervised!({Driver, %{agent_id: agent.id, substrate_pid: test_pid}})
      Driver.execute_event(pid, %{type: :conversation, content: "hello"})
      assert_receive {:execution_complete, action}, 500
      assert action.type == :external_event
    end
  end

  test "registers in AgentRegistry", %{agent: agent} do
    _pid = start_supervised!({Driver, %{agent_id: agent.id}})
    [{pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :driver})
    assert is_pid(pid)
  end
end
