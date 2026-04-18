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
        Task.Supervisor.start_child(Lincoln.TaskSupervisor, fn ->
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

  defp determine_severity(:user_correction), do: "high"
  defp determine_severity(:error_occurred), do: "high"
  defp determine_severity(:thought_loop_gave_up), do: "medium"
  defp determine_severity(:research_failed), do: "medium"
  defp determine_severity(:belief_contradiction), do: "medium"
  defp determine_severity(:slow_operation), do: "low"
  defp determine_severity(:thought_loop_slow), do: "low"
  defp determine_severity(:low_confidence_response), do: "low"
  defp determine_severity(_), do: "medium"
end
