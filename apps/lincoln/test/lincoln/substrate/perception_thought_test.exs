defmodule Lincoln.Substrate.PerceptionThoughtTest do
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Beliefs, Memory}
  alias Lincoln.Memory.Memory, as: MemorySchema
  alias Lincoln.Substrate.PerceptionThought

  setup :verify_on_exit!

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Perception Thought #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "execute/1" do
    test "returns an idle summary when no unprocessed observations exist", %{agent: agent} do
      assert {:ok, "No unprocessed observations"} = PerceptionThought.execute(agent)
    end

    test "marks the observation as processed even when no claim is extracted", %{agent: agent} do
      {:ok, memory} = create_observation(agent, "An ambiguous note with no clear claim")

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok, %{"claim" => "", "confidence" => 0.0, "reasoning" => "no claim"}}
      end)

      assert {:ok, summary} = PerceptionThought.execute(agent)
      assert summary =~ "no extractable claim"

      reloaded = Memory.get_memory!(memory.id)
      assert reloaded.source_context["processed_at"]
      assert Beliefs.list_beliefs(agent, status: "active") == []
    end

    test "forms a belief when the LLM returns a confident claim", %{agent: agent} do
      {:ok, memory} =
        create_observation(
          agent,
          "Article: Erlang processes are isolated by default and have private heaps"
        )

      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.7)} end)

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "claim" => "Erlang processes have private heaps and are isolated by default",
           "confidence" => 0.85,
           "reasoning" => "Source is a technical article"
         }}
      end)

      assert {:ok, summary} = PerceptionThought.execute(agent)
      assert summary =~ "formed belief"

      [belief] = Beliefs.list_beliefs(agent, status: "active")
      assert belief.statement =~ "Erlang processes"
      assert belief.source_type == "observation"

      reloaded = Memory.get_memory!(memory.id)
      assert reloaded.source_context["processed_at"]
      assert belief.id in reloaded.related_belief_ids
    end

    test "does not form a belief when LLM confidence is below threshold", %{agent: agent} do
      {:ok, _memory} = create_observation(agent, "A weak signal: maybe X is true")

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok,
         %{
           "claim" => "X might be true sometimes",
           "confidence" => 0.4,
           "reasoning" => "tentative"
         }}
      end)

      assert {:ok, summary} = PerceptionThought.execute(agent)
      assert summary =~ "too uncertain"

      assert Beliefs.list_beliefs(agent, status: "active") == []
    end

    test "picks the highest-importance unprocessed observation first", %{agent: agent} do
      {:ok, low} = create_observation(agent, "Low importance note", importance: 3)
      {:ok, high} = create_observation(agent, "High importance signal", importance: 9)

      stub(Lincoln.LLMMock, :extract, fn _prompt, _schema, _opts ->
        {:ok, %{"claim" => "", "confidence" => 0.0, "reasoning" => "skip"}}
      end)

      assert {:ok, _} = PerceptionThought.execute(agent)

      assert %MemorySchema{} = reloaded_high = Memory.get_memory!(high.id)
      assert reloaded_high.source_context["processed_at"]

      assert %MemorySchema{} = reloaded_low = Memory.get_memory!(low.id)
      refute reloaded_low.source_context["processed_at"]
    end
  end

  defp create_observation(agent, content, opts \\ []) do
    Memory.create_memory(agent, %{
      content: content,
      memory_type: "observation",
      importance: Keyword.get(opts, :importance, 6),
      source_context: %{"source" => "test"}
    })
  end

  defp fake_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
