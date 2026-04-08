defmodule Lincoln.Substrate.ConversationBridge do
  @moduledoc """
  Routes conversation events to the Substrate process after chat processing.

  The bridge is deliberately optional — chat works whether or not Substrate is running.
  Call `notify/3` after `ConversationHandler.process_message/3` returns.
  """

  require Logger

  alias Lincoln.Substrate
  alias Lincoln.UserModels

  @doc """
  Notify the substrate of a processed conversation message.

  `agent_id` — the agent being talked to
  `message` — the user message content
  `cognitive_metadata` — map returned by ConversationHandler with keys like
    :memories_retrieved, :beliefs_consulted, :contradictions_detected, etc.
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

    event = %{
      type: :conversation,
      content: message,
      metadata: cognitive_metadata,
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
