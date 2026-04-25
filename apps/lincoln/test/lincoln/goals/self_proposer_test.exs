defmodule Lincoln.Goals.SelfProposerTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Goals}
  alias Lincoln.Goals.{Goal, SelfProposer}

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "SelfProposer #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "propose_self_goal/3" do
    test "creates a goal with origin self and pending_user_approval status",
         %{agent: agent} do
      assert {:ok, %Goal{} = goal} =
               SelfProposer.propose_self_goal(
                 agent,
                 "Investigate why I keep circling identity questions"
               )

      assert goal.origin == "self"
      assert goal.status == "pending_user_approval"
    end
  end

  describe "approve/1" do
    test "moves a pending self-goal to active", %{agent: agent} do
      {:ok, goal} = SelfProposer.propose_self_goal(agent, "Try X")

      assert {:ok, approved} = SelfProposer.approve(goal)
      assert approved.status == "active"
      assert approved.origin == "self"
    end

    test "refuses to approve already-active goals", %{agent: agent} do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "user goal"})
      assert {:error, :not_pending_approval} = SelfProposer.approve(goal)
    end
  end

  describe "reject/1" do
    test "marks a pending self-goal abandoned", %{agent: agent} do
      {:ok, goal} = SelfProposer.propose_self_goal(agent, "Try Y")

      assert {:ok, rejected} = SelfProposer.reject(goal)
      assert rejected.status == "abandoned"
    end
  end
end
