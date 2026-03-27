defmodule Lincoln.Autonomy.LearningSession do
  @moduledoc """
  Schema for autonomous learning sessions.

  A learning session represents a continuous period of autonomous
  exploration where Lincoln learns from the web, forms beliefs,
  and potentially modifies his own code.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending running paused stopped completed)

  schema "learning_sessions" do
    field(:status, :string, default: "pending")
    field(:started_at, :utc_datetime)
    field(:stopped_at, :utc_datetime)
    field(:topics_explored, :integer, default: 0)
    field(:beliefs_formed, :integer, default: 0)
    field(:memories_created, :integer, default: 0)
    field(:code_changes_made, :integer, default: 0)
    field(:api_calls_made, :integer, default: 0)
    field(:tokens_used, :integer, default: 0)
    field(:config, :map, default: %{})
    field(:seed_topics, {:array, :string}, default: [])
    field(:reflection_notes, :string)

    belongs_to(:agent, Lincoln.Agents.Agent)

    has_many(:research_topics, Lincoln.Autonomy.ResearchTopic, foreign_key: :session_id)
    has_many(:web_sources, Lincoln.Autonomy.WebSource, foreign_key: :session_id)
    has_many(:code_changes, Lincoln.Autonomy.CodeChange, foreign_key: :session_id)
    has_many(:learning_logs, Lincoln.Autonomy.LearningLog, foreign_key: :session_id)

    timestamps(type: :utc_datetime)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :status,
      :started_at,
      :stopped_at,
      :topics_explored,
      :beliefs_formed,
      :memories_created,
      :code_changes_made,
      :api_calls_made,
      :tokens_used,
      :config,
      :seed_topics,
      :reflection_notes
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
  end

  def create_changeset(session, attrs, agent_id) do
    session
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
  end

  def start_changeset(session) do
    session
    |> change(%{status: "running", started_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  def stop_changeset(session) do
    session
    |> change(%{status: "stopped", stopped_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  def pause_changeset(session) do
    session
    |> change(%{status: "paused"})
  end

  def resume_changeset(session) do
    session
    |> change(%{status: "running"})
  end

  def increment_changeset(session, field, amount \\ 1) do
    current = Map.get(session, field) || 0
    session |> change(%{field => current + amount})
  end

  def running?(session), do: session.status == "running"
  def stopped?(session), do: session.status in ["stopped", "completed"]
end
