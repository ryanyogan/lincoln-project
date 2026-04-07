defmodule Lincoln.Substrate.InferenceTierTest do
  use ExUnit.Case, async: true
  alias Lincoln.Substrate.InferenceTier

  describe "select_tier/2" do
    test "returns :local for score below ollama threshold" do
      assert :local = InferenceTier.select_tier(0.0)
      assert :local = InferenceTier.select_tier(0.1)
      assert :local = InferenceTier.select_tier(0.29)
    end

    test "returns :ollama for score in middle range" do
      assert :ollama = InferenceTier.select_tier(0.3)
      assert :ollama = InferenceTier.select_tier(0.5)
      assert :ollama = InferenceTier.select_tier(0.69)
    end

    test "returns :claude for high score" do
      assert :claude = InferenceTier.select_tier(0.7)
      assert :claude = InferenceTier.select_tier(0.9)
      assert :claude = InferenceTier.select_tier(1.0)
    end

    test "forces :local when budget is :minimal regardless of score" do
      assert :local = InferenceTier.select_tier(0.9, budget: :minimal)
      assert :local = InferenceTier.select_tier(1.0, budget: :minimal)
    end

    test "respects custom thresholds" do
      assert :local = InferenceTier.select_tier(0.4, ollama_threshold: 0.5)

      assert :ollama =
               InferenceTier.select_tier(0.4, ollama_threshold: 0.3, claude_threshold: 0.8)

      assert :claude = InferenceTier.select_tier(0.6, claude_threshold: 0.5)
    end

    test "non-minimal budgets don't force local" do
      assert :claude = InferenceTier.select_tier(0.9, budget: :full)
      assert :claude = InferenceTier.select_tier(0.9, budget: :moderate)
      assert :claude = InferenceTier.select_tier(0.9, budget: :conservative)
    end

    test "accepts integer scores" do
      assert :claude = InferenceTier.select_tier(1)
      assert :local = InferenceTier.select_tier(0)
    end
  end

  describe "execute_at_tier/3" do
    test "returns {:ok, :skipped} for :local tier" do
      assert {:ok, :skipped} = InferenceTier.execute_at_tier(:local, [], [])

      assert {:ok, :skipped} =
               InferenceTier.execute_at_tier(:local, [%{role: "user", content: "test"}], [])
    end
  end
end
