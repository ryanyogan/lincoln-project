defmodule Lincoln.BeliefsDedupTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Beliefs}

  @vector_dim 384

  defp make_embedding(seed) do
    # Generate a deterministic normalized vector from a seed
    rng = :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    {values, _} =
      Enum.map_reduce(1..@vector_dim, rng, fn _, state ->
        {val, new_state} = :rand.uniform_s(state)
        {val, new_state}
      end)

    # Normalize to unit vector
    mag = :math.sqrt(Enum.reduce(values, 0.0, fn x, acc -> acc + x * x end))
    Enum.map(values, &(&1 / mag))
  end

  defp similar_embedding(base, similarity) do
    # Create an embedding with approximate cosine similarity to base
    # Mix base with random noise to get target similarity
    noise = make_embedding(999_999)
    # similarity ≈ cos(θ), so mix: result = similarity*base + sqrt(1-sim²)*noise
    orthogonal_weight = :math.sqrt(max(0, 1.0 - similarity * similarity))

    mixed =
      Enum.zip(base, noise)
      |> Enum.map(fn {b, n} -> similarity * b + orthogonal_weight * n end)

    # Renormalize
    mag = :math.sqrt(Enum.reduce(mixed, 0.0, fn x, acc -> acc + x * x end))
    Enum.map(mixed, &(&1 / mag))
  end

  describe "creation-time dedup" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Dedup Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "strengthens existing belief instead of creating duplicate when similarity > 0.90", %{
      agent: agent
    } do
      base_emb = make_embedding(42)

      {:ok, original} =
        Beliefs.create_belief(agent, %{
          statement: "Elixir uses pattern matching extensively",
          source_type: "observation",
          confidence: 0.7,
          entrenchment: 3,
          embedding: Pgvector.new(base_emb)
        })

      # Create a very similar embedding (>0.90 similarity)
      dup_emb = similar_embedding(base_emb, 0.95)

      {:ok, result} =
        Beliefs.create_belief(agent, %{
          statement: "Elixir relies heavily on pattern matching",
          source_type: "observation",
          confidence: 0.6,
          embedding: Pgvector.new(dup_emb)
        })

      # Should return the strengthened original, not create a new belief
      assert result.id == original.id
      assert result.confidence > original.confidence

      # Verify only one belief exists
      beliefs = Beliefs.list_beliefs(agent)
      assert length(beliefs) == 1
    end

    test "creates new belief when similarity < 0.90", %{agent: agent} do
      base_emb = make_embedding(42)

      {:ok, original} =
        Beliefs.create_belief(agent, %{
          statement: "Elixir uses pattern matching",
          source_type: "observation",
          confidence: 0.7,
          embedding: Pgvector.new(base_emb)
        })

      # Create a dissimilar embedding
      different_emb = make_embedding(100)

      {:ok, result} =
        Beliefs.create_belief(agent, %{
          statement: "Rust has a strong type system",
          source_type: "observation",
          confidence: 0.6,
          embedding: Pgvector.new(different_emb)
        })

      assert result.id != original.id
      beliefs = Beliefs.list_beliefs(agent)
      assert length(beliefs) == 2
    end

    test "skips dedup when no embedding provided", %{agent: agent} do
      {:ok, _b1} =
        Beliefs.create_belief(agent, %{
          statement: "First belief",
          source_type: "observation",
          confidence: 0.7
        })

      {:ok, b2} =
        Beliefs.create_belief(agent, %{
          statement: "First belief",
          source_type: "observation",
          confidence: 0.7
        })

      # Without embeddings, dedup cannot fire — both created
      beliefs = Beliefs.list_beliefs(agent)
      assert length(beliefs) == 2
      assert b2.confidence == 0.7
    end
  end

  describe "consolidation with lowered thresholds" do
    setup do
      {:ok, agent} =
        Agents.create_agent(%{name: "Consolidation Agent #{System.unique_integer()}"})

      %{agent: agent}
    end

    test "merges beliefs with similarity >= 0.90 (high confidence)", %{agent: agent} do
      base_emb = make_embedding(10)
      similar_emb = similar_embedding(base_emb, 0.92)

      # Create without embeddings to bypass creation-time dedup
      {:ok, b1} =
        Beliefs.create_belief(agent, %{
          statement: "Concurrency is important for scalability",
          source_type: "inference",
          confidence: 0.8,
          entrenchment: 5
        })

      {:ok, b2} =
        Beliefs.create_belief(agent, %{
          statement: "Concurrency matters for system scalability",
          source_type: "inference",
          confidence: 0.75,
          entrenchment: 3
        })

      # Add embeddings via direct update (bypassing dedup)
      b1 |> Ecto.Changeset.change(embedding: Pgvector.new(base_emb)) |> Repo.update!()
      b2 |> Ecto.Changeset.change(embedding: Pgvector.new(similar_emb)) |> Repo.update!()

      result = Beliefs.consolidate_similar(agent)
      assert result.merged >= 1

      active_beliefs = Beliefs.list_beliefs(agent, status: "active")
      assert length(active_beliefs) == 1
    end

    test "merges low-confidence beliefs at lower threshold (0.82)", %{agent: agent} do
      base_emb = make_embedding(20)
      similar_emb = similar_embedding(base_emb, 0.85)

      {:ok, b1} =
        Beliefs.create_belief(agent, %{
          statement: "Maybe functional programming is better",
          source_type: "inference",
          confidence: 0.3,
          entrenchment: 2
        })

      {:ok, b2} =
        Beliefs.create_belief(agent, %{
          statement: "Perhaps FP is superior",
          source_type: "inference",
          confidence: 0.35,
          entrenchment: 2
        })

      b1 |> Ecto.Changeset.change(embedding: Pgvector.new(base_emb)) |> Repo.update!()
      b2 |> Ecto.Changeset.change(embedding: Pgvector.new(similar_emb)) |> Repo.update!()

      result = Beliefs.consolidate_similar(agent)
      assert result.merged >= 1
    end
  end

  describe "multi-factor consolidation winner selection" do
    setup do
      {:ok, agent} = Agents.create_agent(%{name: "Winner Agent #{System.unique_integer()}"})
      %{agent: agent}
    end

    test "multi-factor scoring uses entrenchment, recency, and revision count", %{agent: agent} do
      base_emb = make_embedding(30)
      similar_emb = similar_embedding(base_emb, 0.95)

      # Create both beliefs without embeddings
      {:ok, old} =
        Beliefs.create_belief(agent, %{
          statement: "Old entrenched belief about AI",
          source_type: "training",
          confidence: 0.8,
          entrenchment: 6
        })

      {:ok, recent} =
        Beliefs.create_belief(agent, %{
          statement: "Recent revised belief about AI",
          source_type: "observation",
          confidence: 0.7,
          entrenchment: 3,
          revision_count: 5
        })

      # Backdate the old belief
      two_weeks_ago =
        DateTime.utc_now() |> DateTime.add(-14 * 86_400, :second) |> DateTime.truncate(:second)

      old |> Ecto.Changeset.change(updated_at: two_weeks_ago) |> Repo.update!()

      # Add embeddings
      old |> Ecto.Changeset.change(embedding: Pgvector.new(base_emb)) |> Repo.update!()
      recent |> Ecto.Changeset.change(embedding: Pgvector.new(similar_emb)) |> Repo.update!()

      Beliefs.consolidate_similar(agent)

      active = Beliefs.list_beliefs(agent, status: "active")
      assert length(active) == 1

      # The consolidation_score formula: entrenchment*3 + recency(2 if recent) + revision_count
      # old: 6*3 + 0 + 0 = 18
      # recent: 3*3 + 2 + 5 = 16
      # Old wins due to higher entrenchment weight
      winner = hd(active)
      assert winner.id == old.id
    end
  end
end
