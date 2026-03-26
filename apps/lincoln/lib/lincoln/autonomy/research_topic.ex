defmodule Lincoln.Autonomy.ResearchTopic do
  @moduledoc """
  Schema for research topics in the learning queue.

  Topics are discovered through:
  - Seed topics (initial interests)
  - Discovered references from other topics
  - Curiosity (generated questions)
  - Gap-filling (things Lincoln couldn't answer)
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @sources ~w(seed discovered curiosity gap reflection)
  @statuses ~w(pending in_progress completed skipped failed)

  schema "research_topics" do
    field(:topic, :string)
    field(:source, :string, default: "discovered")
    field(:priority, :integer, default: 5)
    field(:status, :string, default: "pending")
    field(:depth, :integer, default: 0)
    field(:context, :string)
    field(:started_at, :utc_datetime)
    field(:completed_at, :utc_datetime)
    field(:facts_extracted, :integer, default: 0)
    field(:beliefs_formed, :integer, default: 0)
    field(:child_topics_discovered, :integer, default: 0)
    field(:error_message, :string)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:session, Lincoln.Autonomy.LearningSession)
    belongs_to(:parent_topic, Lincoln.Autonomy.ResearchTopic)

    has_many(:child_topics, Lincoln.Autonomy.ResearchTopic, foreign_key: :parent_topic_id)
    has_many(:web_sources, Lincoln.Autonomy.WebSource, foreign_key: :topic_id)
    has_many(:learning_logs, Lincoln.Autonomy.LearningLog, foreign_key: :topic_id)

    timestamps(type: :utc_datetime)
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [
      :topic,
      :source,
      :priority,
      :status,
      :depth,
      :context,
      :started_at,
      :completed_at,
      :facts_extracted,
      :beliefs_formed,
      :child_topics_discovered,
      :error_message,
      :parent_topic_id
    ])
    |> validate_required([:topic, :source, :status])
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:priority, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:depth, greater_than_or_equal_to: 0)
  end

  def create_changeset(topic, attrs, agent_id, session_id) do
    topic
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
    |> put_change(:session_id, session_id)
  end

  def start_changeset(topic) do
    topic
    |> change(%{status: "in_progress", started_at: DateTime.utc_now()})
  end

  def complete_changeset(topic, facts_count, beliefs_count, children_count) do
    topic
    |> change(%{
      status: "completed",
      completed_at: DateTime.utc_now(),
      facts_extracted: facts_count,
      beliefs_formed: beliefs_count,
      child_topics_discovered: children_count
    })
  end

  def fail_changeset(topic, error_message) do
    topic
    |> change(%{
      status: "failed",
      completed_at: DateTime.utc_now(),
      error_message: error_message
    })
  end

  def skip_changeset(topic, reason) do
    topic
    |> change(%{
      status: "skipped",
      completed_at: DateTime.utc_now(),
      error_message: reason
    })
  end
end
