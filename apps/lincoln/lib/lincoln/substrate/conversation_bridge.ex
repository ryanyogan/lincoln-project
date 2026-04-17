defmodule Lincoln.Substrate.ConversationBridge do
  @moduledoc """
  Bidirectional bridge between conversations and the cognitive substrate.

  The bridge is deliberately optional — chat works whether or not Substrate is running.

  Outbound (chat → substrate):
    Call `notify/3` after `ConversationHandler.process_message/3` returns.
    Extracts belief IDs from cognitive metadata so the substrate's Attention
    system becomes aware of conversation topics.

  Inbound (substrate → chat):
    Call `get_substrate_context/1` before processing a message to enrich
    the conversation with what the substrate is currently thinking about.
  """

  require Logger

  alias Lincoln.Substrate
  alias Lincoln.Substrate.Trajectory
  alias Lincoln.UserModels

  @doc """
  Notify the substrate of a processed conversation message.

  Extracts belief IDs from cognitive_metadata and includes them in the event
  so the substrate's activation_map can be updated.
  """
  def notify(agent_id, message, cognitive_metadata \\ %{}) do
    session_id =
      Map.get(cognitive_metadata, :conversation_id) ||
        Map.get(cognitive_metadata, "conversation_id") ||
        "default"

    user_content =
      Map.get(cognitive_metadata, :user_content) ||
        Map.get(cognitive_metadata, "user_content") ||
        ""

    if is_binary(user_content) and byte_size(user_content) > 0 do
      observe_user_message(agent_id, session_id, user_content)
    end

    # Extract belief IDs from cognitive metadata for substrate activation
    belief_ids = extract_belief_ids(cognitive_metadata)

    event = %{
      type: :conversation,
      content: message,
      metadata: cognitive_metadata,
      belief_ids: belief_ids,
      occurred_at: DateTime.utc_now()
    }

    case Substrate.send_event(agent_id, event) do
      :ok ->
        :ok

      {:error, :not_running} ->
        Logger.debug("[ConversationBridge] Substrate not running for agent #{agent_id}, skipping")
        :ok
    end
  end

  @doc """
  Get the substrate's current cognitive context for conversation enrichment.

  Returns a map with the current focus and recent trajectory, or an empty map
  if the substrate is not running. This is a read-only operation.
  """
  def get_substrate_context(agent_id) do
    case Substrate.get_agent_state(agent_id) do
      {:ok, state} ->
        recent_ticks =
          try do
            Trajectory.get_recent_ticks(agent_id, limit: 3)
          rescue
            e ->
              Logger.debug(
                "[ConversationBridge] Trajectory query failed: #{Exception.message(e)}"
              )

              []
          end

        recent_focuses =
          recent_ticks
          |> Enum.map(fn event ->
            event.event_data["current_focus_statement"]
          end)
          |> Enum.reject(&is_nil/1)

        %{
          current_focus: state.current_focus && Map.get(state.current_focus, :statement),
          tick_count: state.tick_count,
          idle_streak: Map.get(state, :idle_streak, 0),
          recent_focuses: recent_focuses
        }

      {:error, _} ->
        %{}
    end
  end

  defp extract_belief_ids(metadata) when is_map(metadata) do
    keys = [
      :beliefs_consulted,
      :beliefs_formed,
      :beliefs_revised,
      "beliefs_consulted",
      "beliefs_formed",
      "beliefs_revised"
    ]

    keys
    |> Enum.flat_map(fn key ->
      case Map.get(metadata, key) do
        ids when is_list(ids) -> ids
        _ -> []
      end
    end)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp extract_belief_ids(_), do: []

  defp observe_user_message(agent_id, session_id, user_content) do
    Task.start(fn ->
      try do
        UserModels.observe_message(agent_id, to_string(session_id), user_content)
      rescue
        e ->
          Logger.warning(
            "[ConversationBridge] UserModel observation failed: #{Exception.message(e)}"
          )
      end
    end)
  end
end
