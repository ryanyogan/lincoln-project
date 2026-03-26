defmodule Lincoln.Questions.QuestionCluster do
  @moduledoc """
  Schema for grouping related questions.

  Clusters help the agent:
  1. Recognize patterns in its curiosity
  2. Avoid fragmenting related questions
  3. Track broader themes of interest
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active resolved merged)

  schema "question_clusters" do
    field(:theme, :string)
    field(:description, :string)
    field(:centroid_embedding, Pgvector.Ecto.Vector)
    field(:question_count, :integer, default: 0)
    field(:status, :string, default: "active")

    belongs_to(:agent, Lincoln.Agents.Agent)
    has_many(:questions, Lincoln.Questions.Question, foreign_key: :cluster_id)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cluster, attrs) do
    cluster
    |> cast(attrs, [:theme, :description, :centroid_embedding, :status])
    |> validate_required([:theme])
    |> validate_inclusion(:status, @statuses)
  end

  @doc """
  Changeset for creating a new cluster.
  """
  def create_changeset(cluster, attrs, agent_id) do
    cluster
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
  end

  @doc """
  Changeset for updating question count.
  """
  def update_count_changeset(cluster, count) do
    change(cluster, question_count: count)
  end
end
