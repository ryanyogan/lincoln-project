defmodule Lincoln.Substrate.GoalThoughtTest do
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Goals, Memory}
  alias Lincoln.Substrate.GoalThought

  setup :verify_on_exit!

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "GoalThought #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "execute/1" do
    test "returns idle summary when no active goals exist", %{agent: agent} do
      assert {:ok, "No active goals to pursue"} = GoalThought.execute(agent)
    end

    test "records progress and writes a reflection memory on a successful LLM call", %{
      agent: agent
    } do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "Ship the docs", priority: 8})

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "progress" => 0.5,
           "next_step" => "Outline the README sections",
           "reasoning" => "Halfway through scoping"
         }}
      end)

      assert {:ok, summary} = GoalThought.execute(agent)
      assert summary =~ "Ship the docs"
      assert summary =~ "50%"
      assert summary =~ "Outline the README sections"

      reloaded = Goals.get_goal!(goal.id)
      assert reloaded.progress_estimate == 0.5
      assert reloaded.last_evaluated_at

      [memory] = Memory.list_memories_by_type(agent, "reflection")
      assert memory.content =~ "Ship the docs"
      assert memory.source_context["goal_id"] == goal.id
    end

    test "still updates last_evaluated_at when LLM extraction fails", %{agent: agent} do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "Vague goal", priority: 5})

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:error, :timeout}
      end)

      assert {:ok, _summary} = GoalThought.execute(agent)

      reloaded = Goals.get_goal!(goal.id)
      assert reloaded.last_evaluated_at
      # Progress unchanged
      assert reloaded.progress_estimate == 0.0
    end

    test "auto-marks goal achieved when LLM reports progress >= 1.0", %{agent: agent} do
      {:ok, goal} = Goals.create_goal(agent, %{statement: "Done thing", priority: 5})

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok, %{"progress" => 1.0, "next_step" => "celebrate", "reasoning" => "done"}}
      end)

      assert {:ok, _} = GoalThought.execute(agent)
      reloaded = Goals.get_goal!(goal.id)
      assert reloaded.status == "achieved"
    end
  end
end
