defmodule Lincoln.Memory.Memory do
  @moduledoc """
  Schema for a memory - a record of an experience or reflection.

  Memories are the raw material from which beliefs are formed.
  The retrieval system uses a combination of:
  - Recency: more recent memories are more relevant
  - Importance: explicitly marked importance
  - Relevance: semantic similarity to the current query

  Inspired by the Generative Agents paper (Park et al., 2023).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @memory_types ~w(observation reflection conversation plan)

  schema "memories" do
    field(:content, :string)
    field(:summary, :string)
    field(:memory_type, :string)
    field(:importance, :integer, default: 5)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:last_accessed_at, :utc_datetime)
    field(:access_count, :integer, default: 0)
    field(:source_context, :map, default: %{})
    field(:related_belief_ids, {:array, :binary_id}, default: [])
    field(:related_question_id, :binary_id)

    belongs_to(:agent, Lincoln.Agents.Agent)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :content,
      :summary,
      :memory_type,
      :importance,
      :embedding,
      :source_context,
      :related_belief_ids,
      :related_question_id
    ])
    |> validate_required([:content, :memory_type])
    |> validate_inclusion(:memory_type, @memory_types)
    |> validate_number(:importance, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
  end

  @doc """
  Changeset for creating a new memory.
  """
  def create_changeset(memory, attrs, agent_id) do
    memory
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
  end

  @doc """
  Changeset for recording memory access.
  """
  def access_changeset(memory) do
    change(memory,
      last_accessed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      access_count: memory.access_count + 1
    )
  end
end
