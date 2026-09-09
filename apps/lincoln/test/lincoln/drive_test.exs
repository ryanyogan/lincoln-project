defmodule Lincoln.DriveTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Drive}

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Drive Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "record_prediction_error/2" do
    test "inserts a valid prediction error", %{agent: agent} do
      assert {:ok, pe} =
               Drive.record_prediction_error(agent.id, %{
                 thought_id: Ecto.UUID.generate(),
                 impulse_source: "investigation",
                 expected_score: 0.7,
                 actual_outcome: 0.55,
                 prediction_error: -0.15,
                 beliefs_created: 1,
                 findings_created: 1
               })

      assert pe.expected_score == 0.7
      assert pe.actual_outcome == 0.55
      assert pe.prediction_error == -0.15
      assert pe.impulse_source == "investigation"
      assert pe.beliefs_created == 1
    end

    test "rejects invalid impulse source", %{agent: agent} do
      assert {:error, changeset} =
               Drive.record_prediction_error(agent.id, %{
                 thought_id: Ecto.UUID.generate(),
                 impulse_source: "invalid_type",
                 expected_score: 0.5,
                 actual_outcome: 0.5,
                 prediction_error: 0.0
               })

      assert errors_on(changeset).impulse_source
    end

    test "allows nil impulse_source for belief thoughts", %{agent: agent} do
      assert {:ok, pe} =
               Drive.record_prediction_error(agent.id, %{
                 thought_id: Ecto.UUID.generate(),
                 impulse_source: nil,
                 expected_score: 0.5,
                 actual_outcome: 0.25,
                 prediction_error: -0.25
               })

      assert is_nil(pe.impulse_source)
    end
  end

  describe "list_recent_errors/2" do
    test "returns errors ordered by recency", %{agent: agent} do
      for i <- 1..5 do
        {:ok, error} =
          Drive.record_prediction_error(agent.id, %{
            thought_id: "thought_#{i}",
            impulse_source: "curiosity",
            expected_score: 0.5,
            actual_outcome: i * 0.1,
            prediction_error: i * 0.1 - 0.5
          })

        # Explicit times test ordering without relying on same-second insert order.
        timestamp =
          DateTime.utc_now() |> DateTime.add(i - 10, :second) |> DateTime.truncate(:second)

        error |> Ecto.Changeset.change(inserted_at: timestamp) |> Repo.update!()
      end

      errors = Drive.list_recent_errors(agent.id, limit: 3)
      assert length(errors) == 3
      assert hd(errors).thought_id == "thought_5"
    end

    test "filters by impulse_source", %{agent: agent} do
      Drive.record_prediction_error(agent.id, %{
        thought_id: "t1",
        impulse_source: "investigation",
        expected_score: 0.5,
        actual_outcome: 0.8,
        prediction_error: 0.3
      })

      Drive.record_prediction_error(agent.id, %{
        thought_id: "t2",
        impulse_source: "curiosity",
        expected_score: 0.5,
        actual_outcome: 0.2,
        prediction_error: -0.3
      })

      errors = Drive.list_recent_errors(agent.id, impulse_source: "investigation")
      assert length(errors) == 1
      assert hd(errors).impulse_source == "investigation"
    end

    test "filters by since", %{agent: agent} do
      Drive.record_prediction_error(agent.id, %{
        thought_id: "t1",
        impulse_source: "curiosity",
        expected_score: 0.5,
        actual_outcome: 0.5,
        prediction_error: 0.0
      })

      future = DateTime.add(DateTime.utc_now(), 60, :second)
      errors = Drive.list_recent_errors(agent.id, since: future)
      assert errors == []

      all_errors = Drive.list_recent_errors(agent.id)
      assert length(all_errors) == 1
    end
  end

  describe "prune_old_errors/2" do
    test "does not delete recent errors", %{agent: agent} do
      Drive.record_prediction_error(agent.id, %{
        thought_id: "t1",
        impulse_source: "curiosity",
        expected_score: 0.5,
        actual_outcome: 0.5,
        prediction_error: 0.0
      })

      {count, _} = Drive.prune_old_errors(agent.id, hours: 1)
      assert count == 0
      assert length(Drive.list_recent_errors(agent.id)) == 1
    end
  end
end
