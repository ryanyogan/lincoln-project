defmodule Lincoln.Autonomy.LearningLog do
  @moduledoc """
  Schema for detailed activity logging during autonomous learning.

  Provides a complete audit trail of everything Lincoln does during
  a learning session, enabling real-time monitoring and post-session
  analysis.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @activity_types ~w(
    session_start session_stop session_pause session_resume
    topic_start topic_complete topic_skip topic_fail
    fetch extract summarize
    believe memorize question
    reflect evolve code_change
    error budget_warning
  )

  schema "learning_logs" do
    field(:activity_type, :string)
    field(:description, :string)
    field(:details, :map, default: %{})
    field(:tokens_used, :integer, default: 0)
    field(:duration_ms, :integer)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:session, Lincoln.Autonomy.LearningSession)
    belongs_to(:topic, Lincoln.Autonomy.ResearchTopic)

    timestamps(type: :utc_datetime)
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :activity_type,
      :description,
      :details,
      :tokens_used,
      :duration_ms,
      :topic_id
    ])
    |> validate_required([:activity_type, :description])
    |> validate_inclusion(:activity_type, @activity_types)
  end

  def create_changeset(log, attrs, agent_id, session_id) do
    log
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
    |> put_change(:session_id, session_id)
  end

  @doc """
  Creates a log entry with timing information.
  """
  def timed_changeset(log, attrs, agent_id, session_id, started_at) do
    duration_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)

    log
    |> create_changeset(attrs, agent_id, session_id)
    |> put_change(:duration_ms, duration_ms)
  end

  @doc """
  Activity type display helpers.
  """
  def activity_icon(activity_type) do
    case activity_type do
      "session_start" -> "hero-play"
      "session_stop" -> "hero-stop"
      "session_pause" -> "hero-pause"
      "session_resume" -> "hero-play"
      "topic_start" -> "hero-magnifying-glass"
      "topic_complete" -> "hero-check-circle"
      "topic_skip" -> "hero-forward"
      "topic_fail" -> "hero-x-circle"
      "fetch" -> "hero-globe-alt"
      "extract" -> "hero-scissors"
      "summarize" -> "hero-document-text"
      "believe" -> "hero-light-bulb"
      "memorize" -> "hero-archive-box"
      "question" -> "hero-question-mark-circle"
      "reflect" -> "hero-sparkles"
      "evolve" -> "hero-arrow-path"
      "code_change" -> "hero-code-bracket"
      "error" -> "hero-exclamation-triangle"
      "budget_warning" -> "hero-currency-dollar"
      _ -> "hero-bolt"
    end
  end

  def activity_color(activity_type) do
    case activity_type do
      "session_start" -> "success"
      "session_stop" -> "warning"
      "error" -> "error"
      "budget_warning" -> "warning"
      "believe" -> "primary"
      "memorize" -> "secondary"
      "code_change" -> "accent"
      "reflect" -> "info"
      "evolve" -> "accent"
      _ -> "base-content"
    end
  end
end
