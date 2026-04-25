defmodule Lincoln.Goals.DecomposerTest do
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Goals}
  alias Lincoln.Goals.{Decomposer, MethodLibrary}

  setup :verify_on_exit!

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Decomposer #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "decompose/2" do
    test "asks LLM, persists method, creates sub-goals", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "sub_goals" => [
             %{"statement" => "Find the form", "priority" => 8},
             %{"statement" => "Fill it out", "priority" => 7},
             %{"statement" => "Submit it", "priority" => 9}
           ]
         }}
      end)

      {:ok, parent} =
        Goals.create_goal(agent, %{
          statement: "Submit the school forms by Friday",
          priority: 9
        })

      assert {:ok, sub_goals} = Decomposer.decompose(parent)
      assert length(sub_goals) == 3
      assert Enum.all?(sub_goals, fn g -> g.parent_goal_id == parent.id end)
      assert Enum.all?(sub_goals, fn g -> g.origin == "decomposed" end)

      assert [_method] = MethodLibrary.list_methods(agent)
    end

    test "reuses a similar prior method without calling the LLM", %{agent: agent} do
      embedding = fake_embedding(0.5)
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, embedding} end)

      {:ok, _} =
        MethodLibrary.record(
          agent,
          "submit_form",
          [
            %{"statement" => "Find form", "priority" => 7},
            %{"statement" => "Submit form", "priority" => 8}
          ],
          embedding
        )

      # If the LLM is asked, this expect would fail verify_on_exit (it
      # would be unexpected since we asserted no call)
      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        flunk("LLM should not be called when a similar method exists")
      end)

      {:ok, parent} =
        Goals.create_goal(agent, %{statement: "Submit a form for the kids", priority: 8})

      assert {:ok, [a, b]} = Decomposer.decompose(parent)
      assert a.statement == "Find form"
      assert b.statement == "Submit form"
    end

    test "falls back to LLM when embedding service is down", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:error, :embeddings_down} end)

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "sub_goals" => [
             %{"statement" => "Step 1", "priority" => 5}
           ]
         }}
      end)

      {:ok, parent} = Goals.create_goal(agent, %{statement: "Do the thing", priority: 6})

      assert {:ok, [_one]} = Decomposer.decompose(parent)
      # Method library *can't* be populated without an embedding — that's expected
      assert MethodLibrary.list_methods(agent) == []
    end

    test "surfaces LLM failure when no method is cached", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)
      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts -> {:error, :timeout} end)

      {:ok, parent} = Goals.create_goal(agent, %{statement: "Do another thing", priority: 6})

      assert {:error, :timeout} = Decomposer.decompose(parent)
      assert Goals.list_sub_goals(parent) == []
    end
  end

  defp fake_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
