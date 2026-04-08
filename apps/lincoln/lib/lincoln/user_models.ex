defmodule Lincoln.UserModels do
  @moduledoc """
  Theory of Mind — what Lincoln believes about the person it's talking with.

  Tracks recurring topics, question patterns, vocabulary style, and
  engagement history per conversation session.
  """

  require Logger

  alias Lincoln.Repo
  alias Lincoln.UserModels.UserModel

  @max_topics 20
  @technical_markers ~w(function module process genserver ecto migration
    elixir erlang otp beam api database schema query algorithm architecture
    substrate cognition supervisor registry pubsub liveview phoenix)

  @stop_words ~w(about after again against before being between could during
    every itself might other should their there these those through under
    which while would without)

  @doc "Get or create a user model for this agent + session."
  def get_or_create_model(agent_id, session_id)
      when is_binary(agent_id) and is_binary(session_id) do
    case Repo.get_by(UserModel, agent_id: agent_id, session_id: session_id) do
      nil ->
        now = DateTime.utc_now()

        %UserModel{}
        |> UserModel.changeset(%{
          agent_id: agent_id,
          session_id: session_id,
          first_seen_at: now,
          last_seen_at: now
        })
        |> Repo.insert()

      model ->
        {:ok, model}
    end
  end

  @doc "Get user model — returns nil if not found."
  def get_model(agent_id, session_id) do
    Repo.get_by(UserModel, agent_id: agent_id, session_id: session_id)
  end

  @doc """
  Observe a user message and update the model incrementally.
  Extracts topics, increments counters, infers vocabulary style.
  """
  def observe_message(agent_id, session_id, message_content)
      when is_binary(message_content) do
    with {:ok, model} <- get_or_create_model(agent_id, session_id) do
      extracted_topics = extract_topics(message_content)
      is_question = String.contains?(message_content, "?")
      new_style = infer_style(message_content, model.vocabulary_style)

      new_topics =
        (model.topics ++ extracted_topics)
        |> Enum.uniq()
        |> Enum.take(@max_topics)

      model
      |> UserModel.changeset(%{
        message_count: model.message_count + 1,
        question_count: model.question_count + if(is_question, do: 1, else: 0),
        topics: new_topics,
        vocabulary_style: new_style,
        last_seen_at: DateTime.utc_now()
      })
      |> Repo.update()
    end
  end

  @doc "Format user model as context string for LLM prompts."
  def to_context_string(%UserModel{} = model) do
    topics_str =
      if model.topics == [],
        do: "none detected yet",
        else: Enum.join(model.topics, ", ")

    q_ratio =
      if model.message_count > 0,
        do: round(model.question_count / model.message_count * 100),
        else: 0

    """
    User context (#{model.message_count} messages):
    - Topics: #{topics_str}
    - Style: #{model.vocabulary_style || "unknown"}
    - Question ratio: #{q_ratio}%
    """
  end

  def to_context_string(nil), do: ""

  # ── Private ────────────────────────────────────────────────────────────────

  defp extract_topics(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s]/, " ")
    |> String.split()
    |> Enum.filter(fn w -> String.length(w) > 4 and w not in @stop_words end)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp infer_style(text, current_style) do
    words = text |> String.downcase() |> String.split()
    tech_count = Enum.count(words, fn w -> w in @technical_markers end)

    cond do
      tech_count >= 2 -> "technical"
      tech_count == 1 and current_style == "technical" -> "technical"
      current_style in ["technical", "casual"] -> current_style
      true -> "casual"
    end
  end
end
