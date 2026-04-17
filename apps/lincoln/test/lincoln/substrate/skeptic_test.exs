defmodule Lincoln.Substrate.SkepticTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Skeptic

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Skeptic Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "detect_contradictions/1" do
    test "handles agent with no beliefs gracefully", %{agent: agent} do
      assert :ok = Skeptic.detect_contradictions(agent)
    end

    test "handles beliefs without embeddings gracefully", %{agent: agent} do
      {:ok, _belief_a} =
        Beliefs.create_belief(agent, %{
          statement: "Elixir is statically typed",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 5
        })

      {:ok, _belief_b} =
        Beliefs.create_belief(agent, %{
          statement: "Elixir is dynamically typed",
          source_type: "training",
          confidence: 0.8,
          entrenchment: 3
        })

      # No embeddings, so no similarity search possible — should return :ok
      assert :ok = Skeptic.detect_contradictions(agent)
    end

    test "handles single high-confidence belief", %{agent: agent} do
      {:ok, _belief} =
        Beliefs.create_belief(agent, %{
          statement: "The BEAM VM is concurrent",
          source_type: "observation",
          confidence: 0.9,
          entrenchment: 5
        })

      assert :ok = Skeptic.detect_contradictions(agent)
    end

    test "handles beliefs below confidence threshold", %{agent: agent} do
      {:ok, _belief} =
        Beliefs.create_belief(agent, %{
          statement: "Uncertain belief",
          source_type: "observation",
          confidence: 0.3,
          entrenchment: 1
        })

      # Below 0.7 confidence threshold — won't be picked as target
      assert :ok = Skeptic.detect_contradictions(agent)
    end
  end
end
