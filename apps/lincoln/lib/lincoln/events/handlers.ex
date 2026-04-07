defmodule Lincoln.Events.Handlers do
  @moduledoc """
  Event handlers that respond to Lincoln's cognitive events.
  Detects patterns and queues improvement opportunities.
  """

  require Logger

  alias Lincoln.Agents
  alias Lincoln.Events
  alias Lincoln.Events.Cache

  @doc """
  Handle an event - check for patterns and queue improvements if needed.
  Called asynchronously after event is emitted.
  """
  def handle(%{type: type} = event) do
    case type do
      "thought_loop_gave_up" -> handle_gave_up(event)
      "thought_loop_slow" -> handle_slow(event)
      "user_correction" -> handle_user_correction(event)
      "low_confidence_response" -> handle_low_confidence(event)
      "research_failed" -> handle_research_failed(event)
      "belief_contradiction" -> handle_contradiction(event)
      "error_occurred" -> handle_error(event)
      "improvement_observed" -> handle_improvement_observed(event)
      _ -> :ok
    end
  end

  # =============================================================================
  # Event-Specific Handlers
  # =============================================================================

  defp handle_gave_up(event) do
    agent = Agents.get_agent!(event.agent_id)

    # Check if this is a repeated pattern
    if repeated_struggle?(agent.id, "thought_loop_gave_up", 3, 60) do
      queue_improvement(agent, event, "repeated_gave_up", %{
        priority: 7,
        suggested_focus: "lib/lincoln/cognition/thought_loop.ex"
      })
    end
  end

  defp handle_slow(event) do
    agent = Agents.get_agent!(event.agent_id)

    # Only act if consistently slow
    if repeated_struggle?(agent.id, "thought_loop_slow", 5, 30) do
      queue_improvement(agent, event, "consistent_slowness", %{
        priority: 5,
        suggested_focus: "lib/lincoln/cognition/"
      })
    end
  end

  defp handle_user_correction(event) do
    agent = Agents.get_agent!(event.agent_id)

    # User corrections are high signal - always queue
    queue_improvement(agent, event, "user_correction", %{
      priority: 8,
      suggested_focus: determine_focus_from_correction(event)
    })
  end

  defp handle_low_confidence(event) do
    agent = Agents.get_agent!(event.agent_id)

    # Check for pattern of low confidence in similar topics
    if repeated_struggle?(agent.id, "low_confidence_response", 5, 120) do
      topic = event.related_topic || "general"

      queue_improvement(agent, event, "persistent_low_confidence", %{
        priority: 6,
        suggested_focus: "lib/lincoln/cognition/thought_loop.ex",
        related_topic: topic
      })
    end
  end

  defp handle_research_failed(event) do
    agent = Agents.get_agent!(event.agent_id)

    if repeated_struggle?(agent.id, "research_failed", 3, 60) do
      queue_improvement(agent, event, "research_failures", %{
        priority: 6,
        suggested_focus: "lib/lincoln/workers/autonomous_learning_worker.ex"
      })
    end
  end

  defp handle_contradiction(event) do
    agent = Agents.get_agent!(event.agent_id)

    # Contradictions might indicate belief formation issues
    if repeated_struggle?(agent.id, "belief_contradiction", 3, 120) do
      queue_improvement(agent, event, "frequent_contradictions", %{
        priority: 5,
        suggested_focus: "lib/lincoln/learning/belief_formation.ex"
      })
    end
  end

  defp handle_error(event) do
    agent = Agents.get_agent!(event.agent_id)

    # Errors are serious - lower threshold
    if repeated_struggle?(agent.id, "error_occurred", 2, 30) do
      queue_improvement(agent, event, "recurring_errors", %{
        priority: 9,
        suggested_focus: event.related_code || "lib/lincoln/"
      })
    end
  end

  defp handle_improvement_observed(event) do
    # Learn from the outcome
    outcome = event.metadata["outcome"]
    agent = Agents.get_agent!(event.agent_id)

    case outcome do
      "improved" ->
        Logger.info("Improvement successful for agent #{agent.id}")

      # Could form a belief about what works

      "degraded" ->
        Logger.warning("Improvement degraded performance for agent #{agent.id}")

        # Queue a follow-up improvement
        queue_improvement(agent, event, "previous_improvement_degraded", %{
          priority: 8,
          suggested_focus: event.metadata["file_path"]
        })

      _ ->
        :ok
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp repeated_struggle?(agent_id, event_type, count, window_minutes) do
    Cache.pattern_exists?(agent_id, event_type, count, window_minutes)
  end

  defp queue_improvement(agent, trigger_event, pattern, opts) do
    # Don't queue if there's already a pending opportunity for this pattern
    existing = Events.list_improvement_opportunities(agent, status: "pending")

    if Enum.any?(existing, fn opp -> opp.pattern == pattern end) do
      Logger.debug("Improvement opportunity already exists for pattern: #{pattern}")
    else
      attrs = %{
        agent_id: agent.id,
        trigger_event_id: trigger_event.id,
        pattern: pattern,
        priority: opts[:priority] || 5,
        suggested_focus: opts[:suggested_focus],
        analysis: %{
          trigger_context: trigger_event.context,
          related_topic: opts[:related_topic] || trigger_event.related_topic
        }
      }

      case Events.create_improvement_opportunity(attrs) do
        {:ok, opp} ->
          Logger.info("Queued improvement opportunity: #{pattern} for agent #{agent.id}")
          {:ok, opp}

        {:error, changeset} ->
          Logger.error("Failed to queue improvement: #{inspect(changeset.errors)}")
          {:error, changeset}
      end

      :already_exists
    end
  end

  defp determine_focus_from_correction(event) do
    # Try to determine what code might be responsible for the incorrect response
    context = event.context || %{}
    topic = event.related_topic

    cond do
      # If related to beliefs
      context["belief_related"] -> "lib/lincoln/learning/belief_formation.ex"
      # If related to memory
      context["memory_related"] -> "lib/lincoln/memory.ex"
      # If related to reasoning
      topic && String.contains?(topic, ["logic", "reason"]) -> "lib/lincoln/cognition/"
      # Default to thought loop
      true -> "lib/lincoln/cognition/thought_loop.ex"
    end
  end
end
