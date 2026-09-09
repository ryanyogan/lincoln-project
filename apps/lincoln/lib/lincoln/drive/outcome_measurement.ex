defmodule Lincoln.Drive.OutcomeMeasurement do
  @moduledoc """
  Before/after snapshot measurement for thought outcomes.

  Takes a count snapshot before a thought spawns, then diffs against
  a fresh snapshot after completion to determine what the thought produced.
  """

  import Ecto.Query

  alias Lincoln.Beliefs.{Belief, BeliefRelationship, BeliefRevision}
  alias Lincoln.Goals.Goal
  alias Lincoln.Questions.{Finding, Question}
  alias Lincoln.Repo

  @outcome_weights %{
    beliefs_created: 0.25,
    beliefs_revised: 0.15,
    beliefs_retracted: 0.20,
    relationships_created: 0.15,
    questions_resolved: 0.20,
    goals_advanced: 0.25,
    findings_created: 0.10
  }

  @outcome_cap 1.5

  def snapshot_before(agent_id) do
    %{
      belief_count: count(Belief, agent_id, status: "active"),
      revision_count: count(BeliefRevision, agent_id),
      retraction_count: count(Belief, agent_id, status: "retracted"),
      relationship_count: count(BeliefRelationship, agent_id),
      resolved_question_count: count(Question, agent_id, status: "answered"),
      finding_count: count(Finding, agent_id),
      goal_progress: goal_progress_snapshot(agent_id),
      taken_at: DateTime.utc_now()
    }
  rescue
    e ->
      require Logger
      Logger.warning("[OutcomeMeasurement] Snapshot failed: #{Exception.message(e)}")
      nil
  end

  def compute_outcome(nil, _agent_id), do: empty_outcome()

  def compute_outcome(before, agent_id) do
    case snapshot_before(agent_id) do
      nil ->
        empty_outcome()

      after_snap ->
        beliefs_created = max(0, after_snap.belief_count - before.belief_count)
        beliefs_revised = max(0, after_snap.revision_count - before.revision_count)
        beliefs_retracted = max(0, after_snap.retraction_count - before.retraction_count)
        relationships_created = max(0, after_snap.relationship_count - before.relationship_count)

        questions_resolved =
          max(0, after_snap.resolved_question_count - before.resolved_question_count)

        findings_created = max(0, after_snap.finding_count - before.finding_count)
        goals_advanced = count_goals_advanced(before.goal_progress, after_snap.goal_progress)

        actual_outcome =
          score_outcome(%{
            beliefs_created: beliefs_created,
            beliefs_revised: beliefs_revised,
            beliefs_retracted: beliefs_retracted,
            relationships_created: relationships_created,
            questions_resolved: questions_resolved,
            goals_advanced: goals_advanced,
            findings_created: findings_created
          })

        %{
          actual_outcome: actual_outcome,
          beliefs_created: beliefs_created,
          beliefs_revised: beliefs_revised,
          beliefs_retracted: beliefs_retracted,
          relationships_created: relationships_created,
          questions_resolved: questions_resolved,
          goals_advanced: goals_advanced,
          findings_created: findings_created
        }
    end
  rescue
    e ->
      require Logger
      Logger.warning("[OutcomeMeasurement] Outcome computation failed: #{Exception.message(e)}")
      empty_outcome()
  end

  def score_outcome(counts) do
    score =
      Enum.reduce(@outcome_weights, 0.0, fn {key, weight}, acc ->
        acc + Map.get(counts, key, 0) * weight
      end)

    min(@outcome_cap, score)
  end

  defp count(Belief, agent_id, status: status) do
    Belief
    |> where([b], b.agent_id == ^agent_id and b.status == ^status)
    |> Repo.aggregate(:count)
  end

  defp count(Question, agent_id, status: status) do
    Question
    |> where([q], q.agent_id == ^agent_id and q.status == ^status)
    |> Repo.aggregate(:count)
  end

  defp count(schema, agent_id) do
    schema
    |> where([r], r.agent_id == ^agent_id)
    |> Repo.aggregate(:count)
  end

  defp goal_progress_snapshot(agent_id) do
    Goal
    |> where([g], g.agent_id == ^agent_id and g.status == "active")
    |> select([g], {g.id, g.progress_estimate})
    |> Repo.all()
    |> Map.new()
  end

  defp count_goals_advanced(before_progress, after_progress) do
    Enum.count(after_progress, fn {goal_id, after_val} ->
      before_val = Map.get(before_progress, goal_id, 0.0)
      (after_val || 0.0) > (before_val || 0.0)
    end)
  end

  defp empty_outcome do
    %{
      actual_outcome: 0.0,
      beliefs_created: 0,
      beliefs_revised: 0,
      beliefs_retracted: 0,
      relationships_created: 0,
      questions_resolved: 0,
      goals_advanced: 0,
      findings_created: 0
    }
  end
end
