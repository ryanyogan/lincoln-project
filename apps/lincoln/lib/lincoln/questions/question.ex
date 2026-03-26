defmodule Lincoln.Questions.Question do
  @moduledoc """
  Schema for a question - something the agent wants to know.

  Questions drive the curiosity system. They have:
  - Semantic hash: for detecting duplicate/similar questions (loop prevention)
  - Cluster membership: for grouping related questions
  - Resolution tracking: to know when questions are answered

  The loop detection system is critical for avoiding the problem
  seen in the Telegram bot - asking the same question repeatedly.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(open answered abandoned merged)

  schema "questions" do
    field(:question, :string)
    field(:context, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:semantic_hash, :string)
    field(:status, :string, default: "open")
    field(:resolved_at, :utc_datetime)
    field(:priority, :integer, default: 5)
    field(:investigate_after, :utc_datetime)
    field(:times_asked, :integer, default: 1)
    field(:last_asked_at, :utc_datetime)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:cluster, Lincoln.Questions.QuestionCluster)
    belongs_to(:resolved_by_finding, Lincoln.Questions.Finding)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(question, attrs) do
    question
    |> cast(attrs, [
      :question,
      :context,
      :embedding,
      :semantic_hash,
      :status,
      :priority,
      :investigate_after,
      :cluster_id
    ])
    |> validate_required([:question])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:priority, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
  end

  @doc """
  Changeset for creating a new question.
  """
  def create_changeset(question, attrs, agent_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    question
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
    |> put_change(:last_asked_at, now)
  end

  @doc """
  Changeset for marking a question as answered.
  """
  def resolve_changeset(question, finding_id) do
    change(question,
      status: "answered",
      resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      resolved_by_finding_id: finding_id
    )
  end

  @doc """
  Changeset for recording that the question was asked again.
  """
  def asked_again_changeset(question) do
    change(question,
      times_asked: question.times_asked + 1,
      last_asked_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end

  @doc """
  Changeset for abandoning a question.
  """
  def abandon_changeset(question) do
    change(question, status: "abandoned")
  end

  @doc """
  Changeset for merging into another question.
  """
  def merge_changeset(question, target_question_id) do
    change(question,
      status: "merged",
      context: "Merged into question #{target_question_id}"
    )
  end
end
