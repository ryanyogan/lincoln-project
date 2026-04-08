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
  def activity_icon("session_start"), do: "hero-play"
  def activity_icon("session_stop"), do: "hero-stop"
  def activity_icon("session_pause"), do: "hero-pause"
  def activity_icon("session_resume"), do: "hero-play"
  def activity_icon("topic_start"), do: "hero-magnifying-glass"
  def activity_icon("topic_complete"), do: "hero-check-circle"
  def activity_icon("topic_skip"), do: "hero-forward"
  def activity_icon("topic_fail"), do: "hero-x-circle"
  def activity_icon("fetch"), do: "hero-globe-alt"
  def activity_icon("extract"), do: "hero-scissors"
  def activity_icon("summarize"), do: "hero-document-text"
  def activity_icon("believe"), do: "hero-light-bulb"
  def activity_icon("memorize"), do: "hero-archive-box"
  def activity_icon("question"), do: "hero-question-mark-circle"
  def activity_icon("reflect"), do: "hero-sparkles"
  def activity_icon("evolve"), do: "hero-arrow-path"
  def activity_icon("code_change"), do: "hero-code-bracket"
  def activity_icon("error"), do: "hero-exclamation-triangle"
  def activity_icon("budget_warning"), do: "hero-currency-dollar"
  def activity_icon(_), do: "hero-bolt"

  def activity_color("session_start"), do: "success"
  def activity_color("session_stop"), do: "warning"
  def activity_color("error"), do: "error"
  def activity_color("budget_warning"), do: "warning"
  def activity_color("believe"), do: "primary"
  def activity_color("memorize"), do: "secondary"
  def activity_color("code_change"), do: "accent"
  def activity_color("reflect"), do: "info"
  def activity_color("evolve"), do: "accent"
  def activity_color(_), do: "base-content"
end
