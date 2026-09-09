defmodule Lincoln.Drive.OutcomeMeasurementTest do
  use Lincoln.DataCase, async: true

  alias Lincoln.{Agents, Beliefs}
  alias Lincoln.Drive.OutcomeMeasurement

  setup do
    {:ok, agent} = Agents.create_agent(%{name: "Outcome Test #{System.unique_integer()}"})
    %{agent: agent}
  end

  describe "snapshot_before/1" do
    test "returns correct counts for empty agent", %{agent: agent} do
      snap = OutcomeMeasurement.snapshot_before(agent.id)

      assert snap.belief_count == 0
      assert snap.revision_count == 0
      assert snap.retraction_count == 0
      assert snap.relationship_count == 0
      assert snap.resolved_question_count == 0
      assert snap.finding_count == 0
      assert snap.goal_progress == %{}
      assert %DateTime{} = snap.taken_at
    end

    test "counts active beliefs", %{agent: agent} do
      {:ok, _} =
        Beliefs.create_belief(agent, %{
          statement: "Test belief",
          source_type: "observation",
          confidence: 0.8
        })

      snap = OutcomeMeasurement.snapshot_before(agent.id)
      assert snap.belief_count == 1
    end
  end

  describe "compute_outcome/2" do
    test "returns empty outcome for nil snapshot", %{agent: agent} do
      outcome = OutcomeMeasurement.compute_outcome(nil, agent.id)
      assert outcome.actual_outcome == 0.0
      assert outcome.beliefs_created == 0
    end

    test "detects new beliefs created between snapshots", %{agent: agent} do
      before = OutcomeMeasurement.snapshot_before(agent.id)

      {:ok, _} =
        Beliefs.create_belief(agent, %{
          statement: "New belief",
          source_type: "inference",
          confidence: 0.7
        })

      outcome = OutcomeMeasurement.compute_outcome(before, agent.id)
      assert outcome.beliefs_created == 1
      assert outcome.actual_outcome > 0.0
    end

    test "detects belief revisions between snapshots", %{agent: agent} do
      {:ok, belief} =
        Beliefs.create_belief(agent, %{
          statement: "Revisable belief",
          source_type: "observation",
          confidence: 0.5
        })

      before = OutcomeMeasurement.snapshot_before(agent.id)

      Beliefs.strengthen_belief(belief, "new evidence")

      outcome = OutcomeMeasurement.compute_outcome(before, agent.id)
      assert outcome.beliefs_revised == 1
      assert outcome.actual_outcome > 0.0
    end

    test "no-op thought produces zero outcome", %{agent: agent} do
      before = OutcomeMeasurement.snapshot_before(agent.id)
      outcome = OutcomeMeasurement.compute_outcome(before, agent.id)

      assert outcome.actual_outcome == 0.0
      assert outcome.beliefs_created == 0
      assert outcome.beliefs_revised == 0
      assert outcome.beliefs_retracted == 0
    end
  end

  describe "score_outcome/1" do
    test "zero for empty counts" do
      assert OutcomeMeasurement.score_outcome(%{
               beliefs_created: 0,
               beliefs_revised: 0,
               beliefs_retracted: 0,
               relationships_created: 0,
               questions_resolved: 0,
               goals_advanced: 0,
               findings_created: 0
             }) == 0.0
    end

    test "productive thought scores around 0.55" do
      score =
        OutcomeMeasurement.score_outcome(%{
          beliefs_created: 1,
          beliefs_revised: 0,
          beliefs_retracted: 0,
          relationships_created: 0,
          questions_resolved: 1,
          goals_advanced: 0,
          findings_created: 1
        })

      assert_in_delta score, 0.55, 0.01
    end

    test "caps at 1.5" do
      score =
        OutcomeMeasurement.score_outcome(%{
          beliefs_created: 5,
          beliefs_revised: 5,
          beliefs_retracted: 5,
          relationships_created: 5,
          questions_resolved: 5,
          goals_advanced: 5,
          findings_created: 5
        })

      assert score == 1.5
    end
  end
end
