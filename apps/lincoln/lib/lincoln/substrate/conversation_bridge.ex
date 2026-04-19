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

  alias Lincoln.{Agents, Beliefs, Memory, Substrate}
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
      record_conversation_memory(agent_id, user_content, message, session_id)
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
        agent = state.agent
        beliefs = safe_query(fn -> Beliefs.list_beliefs(agent, status: "active") end, [])
        trajectory = safe_query(fn -> Trajectory.summary(agent_id, hours: 1) end, nil)
        focus_history = safe_query(fn -> Trajectory.focus_history(agent_id, limit: 10) end, [])

        %{
          running: true,
          tick_count: state.tick_count,
          idle_streak: Map.get(state, :idle_streak, 0),
          current_focus: state.current_focus && Map.get(state.current_focus, :statement),
          current_score: state.last_attention_score,
          beliefs: format_beliefs_for_prompt(beliefs),
          belief_count: length(beliefs),
          trajectory: trajectory,
          focus_history: format_focus_history(focus_history)
        }

      {:error, _} ->
        %{running: false}
    end
  end

  defp safe_query(fun, default) do
    fun.()
  rescue
    e ->
      Logger.debug("[ConversationBridge] Query failed: #{Exception.message(e)}")
      default
  end

  defp format_beliefs_for_prompt(beliefs) do
    beliefs
    |> Enum.sort_by(& &1.confidence, :desc)
    |> Enum.map_join("\n", fn b ->
      conf = round(b.confidence * 100)
      "- [e=#{b.entrenchment} c=#{conf}% src=#{b.source_type}] #{b.statement}"
    end)
  end

  defp format_focus_history(history) do
    history
    |> Enum.map_join("\n", fn change ->
      statement = String.slice(change.statement || "?", 0, 60)
      score = if change.score, do: Float.round(change.score, 2), else: "?"
      "- tick #{change.tick}: #{statement} (score #{score})"
    end)
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

  defp record_conversation_memory(agent_id, user_content, lincoln_response, session_id) do
    # Only record meaningful exchanges (skip very short messages like "hi")
    if String.length(user_content) > 20 or String.length(to_string(lincoln_response)) > 50 do
      Task.Supervisor.start_child(Lincoln.TaskSupervisor, fn ->
        try do
          agent = Agents.get_agent!(agent_id)

          user_snippet = String.slice(user_content, 0, 200)
          response_snippet = String.slice(to_string(lincoln_response), 0, 300)

          content =
            "Conversation exchange — User: #{user_snippet}" <>
              if(String.length(user_content) > 200, do: "...", else: "") <>
              " | Lincoln: #{response_snippet}" <>
              if(String.length(to_string(lincoln_response)) > 300, do: "...", else: "")

          importance = if String.length(user_content) > 100, do: 6, else: 4

          Memory.record_conversation(agent, content,
            importance: importance,
            context: %{conversation_id: session_id, source: "chat"}
          )
        rescue
          e ->
            Logger.warning(
              "[ConversationBridge] Conversation memory failed: #{Exception.message(e)}"
            )
        end
      end)
    end
  end

  defp observe_user_message(agent_id, session_id, user_content) do
    Task.Supervisor.start_child(Lincoln.TaskSupervisor, fn ->
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
