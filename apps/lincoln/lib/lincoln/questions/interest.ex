defmodule Lincoln.Questions.Interest do
  @moduledoc """
  Schema for an interest - a topic the agent is curious about.

  Interests drive the curiosity system at a higher level than questions.
  They represent ongoing areas of attention.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @origin_types ~w(emergent assigned derived)
  @statuses ~w(active satisfied dormant)

  schema "interests" do
    field(:topic, :string)
    field(:description, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:intensity, :float, default: 0.5)
    field(:origin_type, :string)
    field(:last_explored_at, :utc_datetime)
    field(:exploration_count, :integer, default: 0)
    field(:status, :string, default: "active")

    belongs_to(:agent, Lincoln.Agents.Agent)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(interest, attrs) do
    interest
    |> cast(attrs, [
      :topic,
      :description,
      :embedding,
      :intensity,
      :origin_type,
      :status
    ])
    |> validate_required([:topic, :origin_type])
    |> validate_inclusion(:origin_type, @origin_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:intensity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  @doc """
  Changeset for creating an interest.
  """
  def create_changeset(interest, attrs, agent_id) do
    interest
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
  end

  @doc """
  Changeset for recording exploration.
  """
  def explore_changeset(interest) do
    change(interest,
      last_explored_at: DateTime.utc_now() |> DateTime.truncate(:second),
      exploration_count: interest.exploration_count + 1
    )
  end
end
