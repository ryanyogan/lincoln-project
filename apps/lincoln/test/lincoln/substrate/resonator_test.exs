defmodule Lincoln.Substrate.ResonatorTest do
  use Lincoln.DataCase

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Substrate.Resonator

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Resonator Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "detect_cascades/1" do
    test "handles empty belief set gracefully", %{agent: agent} do
      assert :ok = Resonator.detect_cascades(agent)
    end

    test "handles beliefs below cluster threshold", %{agent: agent} do
      for i <- 1..2 do
        Beliefs.create_belief(agent, %{
          statement: "Observation #{i}",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 3
        })
      end

      # Only 2 beliefs, need 3+ for a cluster
      assert :ok = Resonator.detect_cascades(agent)
    end

    test "handles beliefs without embeddings", %{agent: agent} do
      for i <- 1..4 do
        Beliefs.create_belief(agent, %{
          statement: "Observation belief #{i}",
          source_type: "observation",
          confidence: 0.8,
          entrenchment: 3
        })
      end

      # No embeddings — beliefs are filtered out, no clusters formed
      assert :ok = Resonator.detect_cascades(agent)
    end

    test "runs without error on mixed beliefs", %{agent: agent} do
      Beliefs.create_belief(agent, %{
        statement: "Training belief",
        source_type: "training",
        confidence: 0.9,
        entrenchment: 5
      })

      Beliefs.create_belief(agent, %{
        statement: "Observation belief",
        source_type: "observation",
        confidence: 0.7,
        entrenchment: 2
      })

      Beliefs.create_belief(agent, %{
        statement: "Inference belief",
        source_type: "inference",
        confidence: 0.6,
        entrenchment: 3
      })

      assert :ok = Resonator.detect_cascades(agent)
    end
  end
end
