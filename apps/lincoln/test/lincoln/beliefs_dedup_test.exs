defmodule Lincoln.BeliefsDedupTest do
  use Lincoln.DataCase, async: true
  alias Lincoln.{Agents, Beliefs}

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Dedup #{System.unique_integer()}"})
    %{agent: agent, embedding: Pgvector.new([1.0 | List.duplicate(0.0, 383)])}
  end

  test "an identical repeated account does not increase confidence", %{
    agent: agent,
    embedding: embedding
  } do
    attrs = %{
      statement: "I prefer quiet mornings",
      source_type: "testimony",
      source_evidence: "journal:1",
      confidence: 0.6,
      embedding: embedding
    }

    {:ok, original} = Beliefs.create_belief(agent, attrs)

    for _ <- 1..20 do
      {:ok, repeated} = Beliefs.create_belief(agent, attrs)
      assert repeated.id == original.id
      assert repeated.confidence == 0.6
    end

    assert length(Beliefs.list_beliefs(agent)) == 1
  end

  test "even identical embeddings cannot erase a contrary account", %{
    agent: agent,
    embedding: embedding
  } do
    {:ok, original} =
      Beliefs.create_belief(agent, %{
        statement: "I prefer quiet mornings",
        source_type: "testimony",
        confidence: 0.6,
        embedding: embedding
      })

    {:ok, contrary} =
      Beliefs.create_belief(agent, %{
        statement: "I do not prefer quiet mornings",
        source_type: "testimony",
        confidence: 0.8,
        embedding: embedding
      })

    refute contrary.id == original.id
    assert Beliefs.consolidate_similar(agent).merged == 0
    assert length(Beliefs.list_beliefs(agent, status: "active")) == 2
  end

  test "different sources retain their own provenance", %{agent: agent, embedding: embedding} do
    for source <- ["journal:1", "journal:2"] do
      {:ok, _} =
        Beliefs.create_belief(agent, %{
          statement: "I prefer quiet mornings",
          source_type: "testimony",
          source_evidence: source,
          confidence: 0.6,
          embedding: embedding
        })
    end

    assert Beliefs.consolidate_similar(agent).merged == 0
    assert length(Beliefs.list_beliefs(agent)) == 2
  end
end
