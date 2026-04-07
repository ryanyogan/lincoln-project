defmodule Lincoln.Substrate.AttentionTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Attention

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Attention Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "next_thought/1" do
    test "returns oldest belief first", %{agent: agent} do
      {:ok, _b1} =
        Beliefs.create_belief(agent, %{
          statement: "First",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 2
        })

      :timer.sleep(10)

      {:ok, _b2} =
        Beliefs.create_belief(agent, %{
          statement: "Second",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 2
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      {:ok, belief, _score} = Attention.next_thought(pid)
      assert belief.statement == "First"
    end

    test "advances cursor on successive calls", %{agent: agent} do
      {:ok, _b1} =
        Beliefs.create_belief(agent, %{
          statement: "Alpha",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 2
        })

      :timer.sleep(10)

      {:ok, _b2} =
        Beliefs.create_belief(agent, %{
          statement: "Beta",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 2
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      {:ok, b1, _} = Attention.next_thought(pid)
      {:ok, b2, _} = Attention.next_thought(pid)
      assert b1.id != b2.id
      assert b1.statement == "Alpha"
      assert b2.statement == "Beta"
    end

    test "returns nil for agent with no beliefs", %{agent: agent} do
      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      assert {:ok, nil} = Attention.next_thought(pid)
    end

    test "wraps around when all beliefs visited", %{agent: agent} do
      {:ok, _b1} =
        Beliefs.create_belief(agent, %{
          statement: "Only",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 2
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      {:ok, b1, _} = Attention.next_thought(pid)
      {:ok, b2, _} = Attention.next_thought(pid)
      assert b1.id == b2.id
    end

    test "returns flat 0.5 score placeholder", %{agent: agent} do
      {:ok, _b1} =
        Beliefs.create_belief(agent, %{
          statement: "Scored",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 2
        })

      pid = start_supervised!({Attention, %{agent_id: agent.id}})
      {:ok, _belief, score} = Attention.next_thought(pid)
      assert score == 0.5
    end
  end

  test "registers in AgentRegistry", %{agent: agent} do
    _pid = start_supervised!({Attention, %{agent_id: agent.id}})
    [{pid, _}] = Registry.lookup(Lincoln.AgentRegistry, {agent.id, :attention})
    assert is_pid(pid)
  end
end
