defmodule Lincoln.Substrate.ConversationBridge do
  @moduledoc """
  Routes conversation events to the Substrate process after chat processing.

  The bridge is deliberately optional — chat works whether or not Substrate is running.
  Call `notify/3` after `ConversationHandler.process_message/3` returns.
  """

  require Logger

  alias Lincoln.Substrate

  @doc """
  Notify the substrate of a processed conversation message.

  `agent_id` — the agent being talked to
  `message` — the user message content
  `cognitive_metadata` — map returned by ConversationHandler with keys like
    :memories_retrieved, :beliefs_consulted, :contradictions_detected, etc.
  """
  def notify(agent_id, message, cognitive_metadata \\ %{}) do
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
end
