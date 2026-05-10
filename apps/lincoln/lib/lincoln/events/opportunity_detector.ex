defmodule Lincoln.Events.OpportunityDetector do
  @moduledoc """
  Automatic detection of improvement opportunities from cognitive metrics.

  Scans the substrate's performance patterns and generates improvement
  opportunities for the ImprovementQueue. Runs periodically from the
  substrate tick loop.
  """

  alias Lincoln.Events
  alias Lincoln.Events.ImprovementQueue

  require Logger

  @max_pending 5

  @doc """
  Run all detection heuristics and enqueue any opportunities found.
  Caps total pending opportunities at #{@max_pending}.
  """
  def scan(agent) do
    status = ImprovementQueue.status(agent)

    if status.pending >= @max_pending do
      Logger.debug("[OpportunityDetector] Queue full (#{status.pending} pending) — skipping scan")
      :queue_full
    else
      detections =
        [
          detect_thought_failure_rate(agent),
          detect_investigation_quality(agent),
          detect_belief_churn(agent),
          detect_persistent_perseveration(agent)
        ]
        |> Enum.reject(&is_nil/1)

      Enum.each(detections, fn {pattern, analysis} ->
        if status.pending < @max_pending and not duplicate_pending?(agent, pattern) do
          ImprovementQueue.enqueue(agent, %{
            pattern: pattern,
            priority: 5,
            analysis: analysis
          })

          Logger.info("[OpportunityDetector] Enqueued opportunity: #{pattern}")
        end
      end)

      {:ok, length(detections)}
    end
  rescue
    e ->
      Logger.debug("[OpportunityDetector] Scan failed: #{Exception.message(e)}")
      {:error, e}
  end

  defp duplicate_pending?(agent, pattern) do
    Events.list_improvement_opportunities(agent, status: "pending")
    |> Enum.any?(fn opp -> opp.pattern == pattern end)
  end

  defp detect_thought_failure_rate(agent) do
    since = DateTime.add(DateTime.utc_now(), -3600, :second)

    completed = Events.count_events(agent, "thought_completed", since) || 0
    failed = Events.count_events(agent, "thought_failed", since) || 0
    total = completed + failed

    if total >= 20 and failed / total > 0.2 do
      {"high_thought_failure_rate",
       %{
         failed: failed,
         total: total,
         rate: Float.round(failed / total, 3),
         window: "1 hour"
       }}
    end
  end

  defp detect_investigation_quality(agent) do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    events = Events.list_events(agent, type: "investigation_completed", since: since, limit: 20)

    confidences =
      events
      |> Enum.map(fn e ->
        payload = e.payload || %{}
        payload["confidence"] || payload[:confidence]
      end)
      |> Enum.reject(&is_nil/1)

    if length(confidences) >= 10 do
      avg = Enum.sum(confidences) / length(confidences)

      if avg < 0.5 do
        {"low_investigation_quality",
         %{
           avg_confidence: Float.round(avg, 3),
           sample_size: length(confidences),
           window: "24 hours"
         }}
      end
    end
  end

  defp detect_belief_churn(agent) do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    created = Events.count_events(agent, "belief_created", since) || 0
    retracted = Events.count_events(agent, "belief_retracted", since) || 0

    if created >= 10 and retracted / max(created, 1) > 0.4 do
      {"high_belief_churn",
       %{
         created: created,
         retracted: retracted,
         churn_rate: Float.round(retracted / max(created, 1), 3),
         window: "24 hours"
       }}
    end
  end

  defp detect_persistent_perseveration(agent) do
    current = agent.attention_params || %{}
    base = current["base_novelty_weight"]

    if base do
      dampening = current["entrenchment_dampening"] || 0.0

      if dampening >= 0.6 do
        {"persistent_perseveration",
         %{
           entrenchment_dampening: dampening,
           boosted_novelty: current["novelty_weight"],
           base_novelty: base
         }}
      end
    end
  end
end
