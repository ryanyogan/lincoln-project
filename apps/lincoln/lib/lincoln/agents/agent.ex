defmodule Lincoln.Agents.Agent do
  @moduledoc """
  Schema for an agent - a persistent learning entity.

  Each agent has its own beliefs, memories, questions, and interests.
  Named after Lincoln Six Echo from "The Island" - an entity that
  begins to question its programmed reality.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active inactive suspended)

  schema "agents" do
    field(:name, :string)
    field(:description, :string)
    field(:personality, :map, default: %{})
    field(:status, :string, default: "active")
    field(:last_active_at, :utc_datetime)

    # Counters (denormalized for performance)
    field(:beliefs_count, :integer, default: 0)
    field(:memories_count, :integer, default: 0)
    field(:questions_asked_count, :integer, default: 0)

    # Associations
    has_many(:beliefs, Lincoln.Beliefs.Belief)
    has_many(:memories, Lincoln.Memory.Memory)
    has_many(:questions, Lincoln.Questions.Question)
    has_many(:interests, Lincoln.Questions.Interest)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :description, :personality, :status, :last_active_at])
    |> validate_required([:name])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:name)
  end

  @doc """
  Changeset for updating activity timestamp.
  """
  def touch_changeset(agent) do
    change(agent, last_active_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for incrementing counters.
  """
  def increment_counter_changeset(agent, counter, amount \\ 1)
      when counter in [:beliefs_count, :memories_count, :questions_asked_count] do
    current = Map.get(agent, counter, 0)
    change(agent, [{counter, current + amount}])
  end
end
