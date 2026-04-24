defmodule Lincoln.Perception.SalienceTest do
  use Lincoln.DataCase, async: true

  import Mox

  alias Lincoln.{Agents, Memory}
  alias Lincoln.Perception.{RawObservation, Salience}

  setup :verify_on_exit!

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Salience Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "score/3 — content shape" do
    test "filters empty content", %{agent: agent} do
      obs = RawObservation.new("test", "")
      assert {:filter, :empty} = Salience.score(agent, obs)
    end

    test "filters whitespace-only content", %{agent: agent} do
      obs = RawObservation.new("test", "   \n\t  ")
      assert {:filter, :empty} = Salience.score(agent, obs)
    end
  end

  describe "score/3 — exact duplicates" do
    test "filters when an identical observation already exists", %{agent: agent} do
      content = "The market opened sharply higher."
      {:ok, _} = Memory.record_observation(agent, content)

      obs = RawObservation.new("rss:reuters", content)
      assert {:filter, :exact_duplicate} = Salience.score(agent, obs)
    end

    test "does not filter when content differs by even one character", %{agent: agent} do
      {:ok, _} = Memory.record_observation(agent, "The market opened sharply higher.")

      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.1)} end)

      obs = RawObservation.new("rss:reuters", "The market opened sharply higher!")
      assert {:keep, importance, _embedding} = Salience.score(agent, obs)
      assert importance >= 1 and importance <= 10
    end
  end

  describe "score/3 — kept observations" do
    test "kept observations carry the embedding for downstream retrieval", %{agent: agent} do
      embedding = fake_embedding(0.42)
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, embedding} end)

      obs = RawObservation.new("file_inbox:notes.md", "A genuinely new observation")
      assert {:keep, _importance, ^embedding} = Salience.score(agent, obs)
    end

    test "embedding failure does not block ingestion", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:error, :boom} end)

      obs = RawObservation.new("rss:hn", "Something interesting happened")
      assert {:keep, _importance, nil} = Salience.score(agent, obs)
    end

    test "importance scales with trust_weight", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.1)} end)

      low = RawObservation.new("rss:noisy", "Something", trust_weight: 0.1)
      high = RawObservation.new("file_inbox:curated", "Something else", trust_weight: 0.9)

      assert {:keep, low_importance, _} = Salience.score(agent, low)
      assert {:keep, high_importance, _} = Salience.score(agent, high)
      assert high_importance > low_importance
    end

    test "importance saturates within the schema's 1..10 range", %{agent: agent} do
      stub(Lincoln.EmbeddingsMock, :embed, fn _text, _opts -> {:ok, fake_embedding(0.1)} end)

      obs = RawObservation.new("file_inbox:huge", String.duplicate("x", 1_000), trust_weight: 1.0)
      assert {:keep, importance, _} = Salience.score(agent, obs)
      assert importance >= 1 and importance <= 10
    end
  end

  defp fake_embedding(seed) do
    for i <- 0..383, do: :math.sin(seed + i / 100.0)
  end
end
