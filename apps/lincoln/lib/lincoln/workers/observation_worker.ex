defmodule Lincoln.Workers.ObservationWorker do
  @moduledoc """
  Oban worker that observes the outcome of a code improvement.
  Runs after the observation period to evaluate if the change helped.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias Lincoln.Events
  alias Lincoln.Events.{Emitter, ImprovementQueue}
  alias Lincoln.Autonomy
  alias Lincoln.{Beliefs, Memory}

  @impl true
  def perform(%Oban.Job{args: %{"opportunity_id" => opp_id, "code_change_id" => change_id}}) do
    opportunity = Events.get_improvement_opportunity!(opp_id)
    code_change = Autonomy.get_code_change!(change_id)
    agent = Lincoln.Agents.get_agent!(opportunity.agent_id)

    Logger.info("Observing improvement outcome for opportunity #{opp_id}")

    # Compare metrics before vs after
    outcome = observe_outcome(agent, opportunity, code_change)

    # Update the opportunity
    ImprovementQueue.mark_completed(opportunity, outcome)

    # Emit observation event
    Emitter.emit(agent, :improvement_observed, %{
      opportunity_id: opportunity.id,
      code_change_id: code_change.id,
      outcome: outcome,
      file_path: code_change.file_path,
      pattern: opportunity.pattern
    })

    # Learn from the outcome
    learn_from_outcome(agent, opportunity, code_change, outcome)

    :ok
  end

  defp observe_outcome(agent, opportunity, _code_change) do
    # Check if the pattern that triggered this improvement is still occurring
    pattern_type = pattern_to_event_type(opportunity.pattern)

    if pattern_type do
      # Count recent occurrences
      since = DateTime.add(DateTime.utc_now(), -24, :hour)
      recent_count = Events.count_events(agent, pattern_type, since)

      # Get historical baseline (before the change)
      before_change = opportunity.attempted_at
      baseline_start = DateTime.add(before_change, -24, :hour)
      baseline_count = count_events_in_range(agent, pattern_type, baseline_start, before_change)

      cond do
        # Significant improvement
        recent_count < baseline_count * 0.5 -> "improved"
        # Significant degradation
        recent_count > baseline_count * 1.5 -> "degraded"
        # No significant change
        true -> "no_change"
      end
    else
      # Can't determine outcome, assume no change
      "no_change"
    end
  end

  defp pattern_to_event_type(pattern) do
    case pattern do
      "repeated_gave_up" -> "thought_loop_gave_up"
      "consistent_slowness" -> "thought_loop_slow"
      "user_correction" -> "user_correction"
      "persistent_low_confidence" -> "low_confidence_response"
      "research_failures" -> "research_failed"
      "frequent_contradictions" -> "belief_contradiction"
      "recurring_errors" -> "error_occurred"
      _ -> nil
    end
  end

  defp count_events_in_range(agent, type, start_time, end_time) do
    import Ecto.Query

    Lincoln.Repo.one(
      from(e in Events.Event,
        where: e.agent_id == ^agent.id,
        where: e.type == ^type,
        where: e.inserted_at >= ^start_time and e.inserted_at <= ^end_time,
        select: count(e.id)
      )
    ) || 0
  end

  defp learn_from_outcome(agent, opportunity, code_change, outcome) do
    # Form a belief about what works
    belief_statement =
      case outcome do
        "improved" ->
          "Modifying #{code_change.file_path} to address #{opportunity.pattern} was effective"

        "degraded" ->
          "Modifying #{code_change.file_path} to address #{opportunity.pattern} caused issues and should be reconsidered"

        "no_change" ->
          "Modifying #{code_change.file_path} to address #{opportunity.pattern} had no measurable effect"
      end

    confidence =
      case outcome do
        "improved" -> 0.7
        "degraded" -> 0.7
        "no_change" -> 0.5
      end

    Beliefs.create_belief(agent, %{
      statement: belief_statement,
      confidence: confidence,
      source_type: "self_observation",
      evidence: "Observed outcome of code change #{code_change.id} after modification"
    })

    # Create a memory
    Memory.create_memory(agent, %{
      content: """
      Self-improvement attempt:
      - Pattern: #{opportunity.pattern}
      - File: #{code_change.file_path}
      - Change: #{code_change.description}
      - Outcome: #{outcome}
      """,
      memory_type: "reflection",
      importance: if(outcome == "improved", do: 8, else: 6),
      source_context: %{
        type: "self_improvement",
        code_change_id: code_change.id,
        opportunity_id: opportunity.id,
        outcome: outcome
      }
    })

    # If degraded, queue a follow-up improvement
    if outcome == "degraded" do
      Logger.warning("Previous improvement degraded performance, queuing follow-up")

      ImprovementQueue.enqueue(agent, %{
        pattern: "previous_improvement_degraded",
        priority: 8,
        suggested_focus: code_change.file_path,
        analysis: %{
          previous_change_id: code_change.id,
          previous_outcome: outcome
        }
      })
    end

    :ok
  end
end
