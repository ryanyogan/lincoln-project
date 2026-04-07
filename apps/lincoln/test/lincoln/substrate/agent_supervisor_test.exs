defmodule Lincoln.Substrate.AgentSupervisorTest do
  use Lincoln.DataCase

  alias Lincoln.Substrate

  setup do
    {:ok, agent} =
      Lincoln.Agents.create_agent(%{name: "Supervisor Test #{System.unique_integer()}"})

    on_exit(fn ->
      # Clean up: stop agent if still running
      Substrate.stop_agent(agent.id)
    end)

    %{agent: agent}
  end

  describe "start_agent/1" do
    test "starts all 3 processes", %{agent: agent} do
      assert {:ok, _pid} = Substrate.start_agent(agent.id)

      assert [{_pid1, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :substrate})
      assert [{_pid2, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :attention})
      assert [{_pid3, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :driver})
    end

    test "registers supervisor in registry", %{agent: agent} do
      assert {:ok, _pid} = Substrate.start_agent(agent.id)

      assert [{pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :supervisor})
      assert is_pid(pid)
    end

    test "returns error for nonexistent agent" do
      assert {:error, :agent_not_found} =
               Substrate.start_agent("00000000-0000-0000-0000-000000000000")
    end

    test "returns error if already started", %{agent: agent} do
      assert {:ok, _} = Substrate.start_agent(agent.id)
      assert {:error, :already_started} = Substrate.start_agent(agent.id)
    end
  end

  describe "stop_agent/1" do
    test "terminates all processes", %{agent: agent} do
      {:ok, sup_pid} = Substrate.start_agent(agent.id)

      [{sub_pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :substrate})
      [{att_pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :attention})
      [{drv_pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :driver})

      sub_ref = Process.monitor(sub_pid)
      att_ref = Process.monitor(att_pid)
      drv_ref = Process.monitor(drv_pid)
      sup_ref = Process.monitor(sup_pid)

      assert :ok = Substrate.stop_agent(agent.id)

      assert_receive {:DOWN, ^sup_ref, :process, ^sup_pid, _reason}
      assert_receive {:DOWN, ^sub_ref, :process, ^sub_pid, _reason}
      assert_receive {:DOWN, ^att_ref, :process, ^att_pid, _reason}
      assert_receive {:DOWN, ^drv_ref, :process, ^drv_pid, _reason}

      assert [] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :substrate})
      assert [] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :attention})
      assert [] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :driver})
      assert [] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :supervisor})
    end

    test "returns error if not running" do
      assert {:error, :not_running} =
               Substrate.stop_agent("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "get_agent_state/1" do
    test "returns cognitive state", %{agent: agent} do
      {:ok, _} = Substrate.start_agent(agent.id)
      assert {:ok, state} = Substrate.get_agent_state(agent.id)
      assert state.agent_id == agent.id
      assert state.tick_count == 0
    end

    test "returns error if not running" do
      assert {:error, :not_running} =
               Substrate.get_agent_state("00000000-0000-0000-0000-000000000000")
    end
  end

  describe "send_event/2" do
    test "delivers event to substrate", %{agent: agent} do
      {:ok, _} = Substrate.start_agent(agent.id)

      assert :ok = Substrate.send_event(agent.id, %{type: :test, content: "hello"})

      # Synchronize: ensure the cast has been processed
      {:ok, pid} = Substrate.get_process(agent.id, :substrate)
      _ = :sys.get_state(pid)

      {:ok, state} = Substrate.get_agent_state(agent.id)
      assert length(state.pending_events) == 1
    end

    test "returns error if not running" do
      assert {:error, :not_running} =
               Substrate.send_event("00000000-0000-0000-0000-000000000000", %{type: :test})
    end
  end

  describe "list_running_agents/0" do
    test "returns empty list when no agents running" do
      assert Substrate.list_running_agents() == []
    end

    test "returns running agent ids", %{agent: agent} do
      {:ok, _} = Substrate.start_agent(agent.id)

      running = Substrate.list_running_agents()
      assert agent.id in running
    end

    test "removes agent after stop", %{agent: agent} do
      {:ok, sup_pid} = Substrate.start_agent(agent.id)
      assert agent.id in Substrate.list_running_agents()

      [{sub_pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :substrate})
      sub_ref = Process.monitor(sub_pid)
      sup_ref = Process.monitor(sup_pid)

      :ok = Substrate.stop_agent(agent.id)
      assert_receive {:DOWN, ^sup_ref, :process, ^sup_pid, _reason}
      assert_receive {:DOWN, ^sub_ref, :process, ^sub_pid, _reason}

      refute agent.id in Substrate.list_running_agents()
    end
  end

  describe "get_process/2" do
    test "returns pid for each process type", %{agent: agent} do
      {:ok, _} = Substrate.start_agent(agent.id)

      assert {:ok, pid} = Substrate.get_process(agent.id, :substrate)
      assert is_pid(pid)

      assert {:ok, pid} = Substrate.get_process(agent.id, :attention)
      assert is_pid(pid)

      assert {:ok, pid} = Substrate.get_process(agent.id, :driver)
      assert is_pid(pid)
    end

    test "returns error if not running" do
      assert {:error, :not_running} =
               Substrate.get_process("00000000-0000-0000-0000-000000000000", :substrate)
    end
  end
end
