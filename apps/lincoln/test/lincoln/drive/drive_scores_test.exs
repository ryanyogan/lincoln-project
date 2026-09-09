defmodule Lincoln.Drive.DriveScoresTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Drive}
  alias Lincoln.Drive.DriveScores

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "DriveScores Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "impulse_drive_adjustments/2" do
    test "returns empty map when no prediction errors exist", %{agent: agent} do
      assert DriveScores.impulse_drive_adjustments(agent.id) == %{}
    end

    test "returns positive adjustment for positive PE history", %{agent: agent} do
      for _ <- 1..10 do
        Drive.record_prediction_error(agent.id, %{
          thought_id: Ecto.UUID.generate(),
          impulse_source: "investigation",
          expected_score: 0.3,
          actual_outcome: 0.8,
          prediction_error: 0.5
        })
      end

      adjustments = DriveScores.impulse_drive_adjustments(agent.id)
      assert Map.has_key?(adjustments, "investigation")
      assert adjustments["investigation"] > 0.0
    end

    test "returns negative adjustment for negative PE history", %{agent: agent} do
      for _ <- 1..10 do
        Drive.record_prediction_error(agent.id, %{
          thought_id: Ecto.UUID.generate(),
          impulse_source: "curiosity",
          expected_score: 0.8,
          actual_outcome: 0.0,
          prediction_error: -0.8
        })
      end

      adjustments = DriveScores.impulse_drive_adjustments(agent.id)
      assert Map.has_key?(adjustments, "curiosity")
      assert adjustments["curiosity"] < 0.0
    end

    test "respects floor and ceiling", %{agent: agent} do
      for _ <- 1..20 do
        Drive.record_prediction_error(agent.id, %{
          thought_id: Ecto.UUID.generate(),
          impulse_source: "reflection",
          expected_score: 0.0,
          actual_outcome: 1.5,
          prediction_error: 1.5
        })
      end

      adjustments = DriveScores.impulse_drive_adjustments(agent.id)
      assert adjustments["reflection"] <= 0.15
      assert adjustments["reflection"] >= -0.10
    end

    test "excludes nil impulse_source (belief thoughts)", %{agent: agent} do
      Drive.record_prediction_error(agent.id, %{
        thought_id: Ecto.UUID.generate(),
        impulse_source: nil,
        expected_score: 0.5,
        actual_outcome: 0.5,
        prediction_error: 0.0
      })

      adjustments = DriveScores.impulse_drive_adjustments(agent.id)
      refute Map.has_key?(adjustments, nil)
    end
  end
end
