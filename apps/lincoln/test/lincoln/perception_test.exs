defmodule Lincoln.PerceptionTest do
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Memory, Perception}
  alias Lincoln.Memory.Memory, as: MemorySchema
  alias Lincoln.Perception.RawObservation

  setup :verify_on_exit!

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Perception Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "ingest/2" do
    test "filtered observations do not create a memory", %{agent: agent} do
      assert {:filtered, :empty} =
               Perception.ingest(agent, RawObservation.new("file_inbox:empty.md", ""))

      assert Memory.list_memories_by_type(agent, "observation") == []
    end

    test "kept observations create an observation memory with source context", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      obs =
        RawObservation.new(
          "rss:hn",
          "Headline: a thing happened",
          title: "A thing happened",
          url: "https://example.com/1",
          external_id: "hn:1",
          trust_weight: 0.7,
          metadata: %{"score" => 42}
        )

      assert {:ok, %MemorySchema{} = memory} = Perception.ingest(agent, obs)
      assert memory.memory_type == "observation"
      assert memory.content == "Headline: a thing happened"
      assert memory.importance >= 1 and memory.importance <= 10

      assert memory.source_context["source"] == "rss:hn"
      assert memory.source_context["title"] == "A thing happened"
      assert memory.source_context["url"] == "https://example.com/1"
      assert memory.source_context["external_id"] == "hn:1"
      assert memory.source_context["trust_weight"] == 0.7
      assert memory.source_context["score"] == 42
      assert is_binary(memory.source_context["occurred_at"])
    end

    test "two ingests of the same exact content only create one memory", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      obs = RawObservation.new("file_inbox:dup.md", "Same exact content")

      assert {:ok, _} = Perception.ingest(agent, obs)
      assert {:filtered, :exact_duplicate} = Perception.ingest(agent, obs)

      assert length(Memory.list_memories_by_type(agent, "observation")) == 1
    end

    test "embedding service failure still produces a memory (fault-tolerant ingestion)", %{
      agent: agent
    } do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:error, :embeddings_offline} end)

      assert {:ok, %MemorySchema{} = memory} =
               Perception.ingest(agent, RawObservation.new("file_inbox:doc.md", "Some content"))

      assert is_nil(memory.embedding)
    end

    test "occurred_at defaults to now when not provided", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.5)} end)

      obs = RawObservation.new("file_inbox:fresh.md", "Hello world")
      assert {:ok, memory} = Perception.ingest(agent, obs)

      iso = memory.source_context["occurred_at"]
      assert {:ok, _, _} = DateTime.from_iso8601(iso)
    end
  end

  defp fake_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
