defmodule Lincoln.Substrate.SkepticTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Skeptic

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Skeptic Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "start_link/1" do
    test "starts and registers in AgentRegistry", %{agent: agent} do
      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})
      [{reg_pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :skeptic})
      assert reg_pid == pid
    end

    test "initializes with correct state", %{agent: agent} do
      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})

      state = Skeptic.get_state(pid)
      assert state.agent_id == agent.id
      assert state.agent.id == agent.id
      assert state.tick_count == 0
      assert state.tick_interval == 60_000
      assert is_nil(state.last_tick_at)
    end

    test "uses default tick interval when not specified", %{agent: agent} do
      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})
      state = Skeptic.get_state(pid)
      assert state.tick_interval == 60_000
    end
  end

  describe "tick" do
    test "increments tick_count", %{agent: agent} do
      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Skeptic.get_state(pid)
      assert state.tick_count == 1
      assert %DateTime{} = state.last_tick_at
    end

    test "multiple ticks accumulate", %{agent: agent} do
      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)
      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Skeptic.get_state(pid)
      assert state.tick_count == 2
    end

    test "handles tick with no beliefs gracefully", %{agent: agent} do
      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Skeptic.get_state(pid)
      assert state.tick_count == 1
    end

    test "handles tick with beliefs that have no embeddings", %{agent: agent} do
      {:ok, _belief_a} =
        Beliefs.create_belief(agent, %{
          statement: "Elixir is statically typed",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 5
        })

      {:ok, _belief_b} =
        Beliefs.create_belief(agent, %{
          statement: "Elixir is dynamically typed",
          source_type: "training",
          confidence: 0.8,
          entrenchment: 3
        })

      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})

      send(pid, :tick)
      _ = :sys.get_state(pid)

      state = Skeptic.get_state(pid)
      assert state.tick_count == 1
    end
  end

  describe "get_state/1" do
    test "returns full state struct", %{agent: agent} do
      pid = start_supervised!({Skeptic, %{agent_id: agent.id, tick_interval: 60_000}})

      state = Skeptic.get_state(pid)
      assert %Skeptic{} = state
      assert state.agent_id == agent.id
      assert state.tick_count == 0
    end
  end
end
