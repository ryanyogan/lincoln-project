defmodule Lincoln.Events.Emitter do
  @moduledoc """
  Central event emission point.
  All events flow through here for:
  1. Persistence (Postgres)
  2. Caching (ETS for fast pattern analysis)
  3. Broadcasting (PubSub for UI updates)
  4. Handling (immediate pattern detection)
  """

  require Logger

  alias Lincoln.Events
  alias Lincoln.Events.{Cache, Handlers}
  alias Lincoln.PubSubBroadcaster

  @doc """
  Emit an event for an agent.

  ## Examples

      Emitter.emit(agent, :thought_loop_gave_up, %{
        message: "What is quantum entanglement?",
        iterations: 3,
        final_confidence: 0.35
      })
  """
  def emit(agent, type, data \\ %{}) do
    attrs = build_event_attrs(agent, type, data)

    case Events.create_event(attrs) do
      {:ok, event} ->
        # Store in ETS cache
        Cache.store(event)

        # Broadcast via PubSub
        PubSubBroadcaster.broadcast("agent:#{agent.id}:events", {:event, event})

        # Run immediate handlers (async)
        Task.start(fn ->
          Handlers.handle(event)
        end)

        Logger.debug("Event emitted: #{type} for agent #{agent.id}")
        {:ok, event}

      {:error, changeset} ->
        Logger.error("Failed to emit event: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp build_event_attrs(agent, type, data) do
    %{
      type: to_string(type),
      agent_id: agent.id,
      severity: Map.get(data, :severity, determine_severity(type)),
      context: Map.get(data, :context, %{}),
      duration_ms: Map.get(data, :duration_ms),
      related_topic: Map.get(data, :related_topic),
      related_code: Map.get(data, :related_code),
      metadata:
        Map.drop(data, [
          :severity,
          :context,
          :duration_ms,
          :related_topic,
          :related_code,
          :conversation_id
        ]),
      conversation_id: Map.get(data, :conversation_id)
    }
  end

  defp determine_severity(type) do
    case type do
      :user_correction -> "high"
      :thought_loop_gave_up -> "medium"
      :error_occurred -> "high"
      :research_failed -> "medium"
      :belief_contradiction -> "medium"
      :slow_operation -> "low"
      :thought_loop_slow -> "low"
      :low_confidence_response -> "low"
      _ -> "medium"
    end
  end
end
