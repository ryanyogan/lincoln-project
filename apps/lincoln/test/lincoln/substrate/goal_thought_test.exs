defmodule Lincoln.Substrate.GoalThoughtTest do
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Goals, Memory, Questions}
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

  describe "execute/1 — context-grounded reflection" do
    test "includes relevant beliefs and prior reflections in the LLM prompt", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      {:ok, goal} = Goals.create_goal(agent, %{statement: "Ship the docs", priority: 8})

      # Seed a prior goal-reflection memory tagged to this goal
      {:ok, _} =
        Memory.create_memory(agent, %{
          content: "Goal reflection on 'Ship the docs': progress 10%, next step 'outline'",
          memory_type: "reflection",
          importance: 6,
          source_context: %{"source" => "goal_thought", "goal_id" => goal.id}
        })

      stub(Lincoln.LLMMock, :extract, fn prompt, _schema, _opts ->
        # Prompt must include the prior-reflections section AND the seeded
        # reflection's actual content so the LLM can update against evidence.
        assert prompt =~ "Prior reflections on THIS goal"
        assert prompt =~ "outline"

        {:ok,
         %{
           "progress" => 0.3,
           "next_step" => "Draft the intro paragraph",
           "next_step_kind" => "reflect",
           "reasoning" => "Built on prior outline step"
         }}
      end)

      assert {:ok, _summary} = GoalThought.execute(agent)
    end
  end

  describe "execute/1 — research questions for outward goals" do
    test "queues a high-priority question when next_step_kind is research", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      {:ok, _goal} =
        Goals.create_goal(agent, %{statement: "Understand new database X", priority: 7})

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "progress" => 0.05,
           "next_step" => "Research what makes X distinctive",
           "next_step_kind" => "research",
           "research_question" =>
             "What is the architectural distinctive of database X compared to alternatives?",
           "reasoning" => "no prior context"
         }}
      end)

      assert {:ok, summary} = GoalThought.execute(agent)
      assert summary =~ "queued for investigation"

      [question] = Questions.list_open_questions(agent)
      assert question.question =~ "architectural distinctive"
      # Goal-derived questions are priority 8 — above the curiosity-default 5.
      assert question.priority >= 7
    end

    test "does not queue a question when next_step_kind is not research", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      {:ok, _goal} =
        Goals.create_goal(agent, %{statement: "Synthesize prior beliefs", priority: 5})

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "progress" => 0.2,
           "next_step" => "Reflect on belief A vs B",
           "next_step_kind" => "reflect",
           "research_question" => "",
           "reasoning" => "internal work"
         }}
      end)

      assert {:ok, summary} = GoalThought.execute(agent)
      refute summary =~ "queued for investigation"
      assert Questions.list_open_questions(agent) == []
    end

    test "does not queue when research_question is empty even with research kind", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      {:ok, _goal} = Goals.create_goal(agent, %{statement: "X", priority: 5})

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "progress" => 0.1,
           "next_step" => "Look something up",
           "next_step_kind" => "research",
           "research_question" => "",
           "reasoning" => "no specific question"
         }}
      end)

      assert {:ok, _summary} = GoalThought.execute(agent)
      assert Questions.list_open_questions(agent) == []
    end
  end

  defp fake_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
