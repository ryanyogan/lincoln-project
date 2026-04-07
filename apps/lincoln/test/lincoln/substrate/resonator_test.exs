defmodule Lincoln.Substrate.ResonatorTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Resonator

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Resonator Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "start_link/1" do
    test "starts and registers in AgentRegistry", %{agent: agent} do
      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})
      [{reg_pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :resonator})
      assert reg_pid == pid
    end

    test "initializes with correct state", %{agent: agent} do
      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      state = Resonator.get_state(pid)
      assert state.agent_id == agent.id
      assert state.agent.id == agent.id
      assert state.tick_count == 0
      assert state.tick_interval == 60_000
      assert is_nil(state.last_tick_at)
    end
  end

  describe "tick" do
    test "increments tick_count", %{agent: agent} do
      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Resonator.get_state(pid)
      assert state.tick_count == 1
      assert %DateTime{} = state.last_tick_at
    end

    test "multiple ticks accumulate", %{agent: agent} do
      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)
      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Resonator.get_state(pid)
      assert state.tick_count == 2
    end

    test "handles empty belief set gracefully", %{agent: agent} do
      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Resonator.get_state(pid)
      assert state.tick_count == 1
    end

    test "handles beliefs below cluster threshold", %{agent: agent} do
      for i <- 1..2 do
        Beliefs.create_belief(agent, %{
          statement: "Observation #{i}",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 3
        })
      end

      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      assert Resonator.get_state(pid).tick_count == 1
    end

    test "detects cascade in cluster of 3+ same-source recent beliefs", %{agent: agent} do
      for i <- 1..4 do
        Beliefs.create_belief(agent, %{
          statement: "Observation belief #{i}",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 3
        })
      end

      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      beliefs = Beliefs.list_beliefs(agent)
      first_belief = hd(beliefs)
      supports = Beliefs.find_support_cluster(agent, first_belief.id)

      assert supports != []
    end

    test "does not duplicate relationships on repeated ticks", %{agent: agent} do
      for i <- 1..3 do
        Beliefs.create_belief(agent, %{
          statement: "Training belief #{i}",
          source_type: "training",
          confidence: 0.9,
          entrenchment: 5
        })
      end

      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)
      send(pid, :tick)
      _ = :sys.get_state(pid)

      beliefs = Beliefs.list_beliefs(agent)
      first_belief = hd(beliefs)
      supports = Beliefs.find_support_cluster(agent, first_belief.id)

      # 3 beliefs => 2 support relationships involving the first belief
      assert length(supports) == 2
    end
  end

  describe "get_state/1" do
    test "returns full state struct", %{agent: agent} do
      pid = start_supervised!({Resonator, %{agent_id: agent.id, tick_interval: 60_000}})

      state = Resonator.get_state(pid)
      assert %Resonator{} = state
      assert state.agent_id == agent.id
      assert state.tick_count == 0
    end
  end
end
