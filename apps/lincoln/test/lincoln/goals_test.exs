defmodule Lincoln.GoalsTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Goals}
  alias Lincoln.Goals.Goal

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Goals Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "create_goal/2" do
    test "creates an active user goal by default", %{agent: agent} do
      assert {:ok, %Goal{} = goal} =
               Goals.create_goal(agent, %{statement: "Submit the school forms"})

      assert goal.status == "active"
      assert goal.origin == "user"
      assert goal.priority == 5
      assert goal.progress_estimate == 0.0
      assert goal.agent_id == agent.id
    end

    test "rejects invalid status", %{agent: agent} do
      assert {:error, changeset} =
               Goals.create_goal(agent, %{statement: "X", status: "weird"})

      assert "is invalid" in errors_on(changeset).status
    end

    test "rejects priority outside 1..10", %{agent: agent} do
      assert {:error, changeset} =
               Goals.create_goal(agent, %{statement: "X", priority: 11})

      assert errors_on(changeset).priority |> Enum.any?(&String.contains?(&1, "less than"))
    end

    test "supports parent/sub_goal hierarchy", %{agent: agent} do
      {:ok, parent} = Goals.create_goal(agent, %{statement: "Ship the feature"})

      {:ok, child} =
        Goals.create_goal(agent, %{
          statement: "Write the tests",
          parent_goal_id: parent.id,
          origin: "decomposed"
        })

      assert child.parent_goal_id == parent.id
      assert [%Goal{id: child_id}] = Goals.list_sub_goals(parent)
      assert child_id == child.id
    end
  end

  describe "list_goals/2" do
    test "filters by status and orders by priority", %{agent: agent} do
      {:ok, low} = Goals.create_goal(agent, %{statement: "low", priority: 2})
      {:ok, high} = Goals.create_goal(agent, %{statement: "high", priority: 9})
      {:ok, _archived} = Goals.create_goal(agent, %{statement: "old", status: "achieved"})

      [first, second] = Goals.list_goals(agent, status: "active")
      assert first.id == high.id
      assert second.id == low.id
    end
  end

  describe "count_active_goals/1" do
    test "returns the number of active goals", %{agent: agent} do
      assert Goals.count_active_goals(agent) == 0

      {:ok, _} = Goals.create_goal(agent, %{statement: "a"})
      {:ok, _} = Goals.create_goal(agent, %{statement: "b"})
      {:ok, _} = Goals.create_goal(agent, %{statement: "c", status: "achieved"})

      assert Goals.count_active_goals(agent) == 2
    end
  end

  describe "next_pursuable_goal/2" do
    test "returns nil when no active goals exist", %{agent: agent} do
      assert is_nil(Goals.next_pursuable_goal(agent))
    end

    test "returns the highest-priority unevaluated goal", %{agent: agent} do
      {:ok, _low} = Goals.create_goal(agent, %{statement: "low", priority: 3})
      {:ok, high} = Goals.create_goal(agent, %{statement: "high", priority: 9})

      assert %Goal{id: id} = Goals.next_pursuable_goal(agent)
      assert id == high.id
    end

    test "skips goals evaluated within the staleness window", %{agent: agent} do
      {:ok, fresh} = Goals.create_goal(agent, %{statement: "fresh", priority: 9})
      {:ok, _} = Goals.record_progress(fresh, 0.1)

      assert is_nil(Goals.next_pursuable_goal(agent, stale_seconds: 300))

      # Stale enough → reappears
      assert %Goal{} = Goals.next_pursuable_goal(agent, stale_seconds: 0)
    end
  end

  describe "record_progress/2" do
    test "stamps last_evaluated_at and updates progress", %{agent: agent} do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "test"})

      assert {:ok, updated} = Goals.record_progress(goal, 0.4)
      assert updated.progress_estimate == 0.4
      assert updated.last_evaluated_at
      assert updated.status == "active"
    end

    test "auto-marks achieved when progress reaches 1.0", %{agent: agent} do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "test"})

      assert {:ok, updated} = Goals.record_progress(goal, 1.0)
      assert updated.progress_estimate == 1.0
      assert updated.status == "achieved"
    end

    test "clamps out-of-range progress", %{agent: agent} do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "test"})

      assert {:ok, updated} = Goals.record_progress(goal, -0.5)
      assert updated.progress_estimate == 0.0

      assert {:ok, updated} = Goals.record_progress(goal, 2.0)
      assert updated.progress_estimate == 1.0
    end
  end

  describe "update_status/2" do
    test "changes status and stamps last_evaluated_at", %{agent: agent} do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "test"})

      assert {:ok, updated} = Goals.update_status(goal, "abandoned")
      assert updated.status == "abandoned"
      assert updated.last_evaluated_at
    end
  end
end
