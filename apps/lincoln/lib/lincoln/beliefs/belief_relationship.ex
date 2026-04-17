defmodule Lincoln.Beliefs.BeliefRelationship do
  @moduledoc """
  Schema for relationships between beliefs.

  Relationships capture how beliefs interact:
  - contradicts: beliefs that directly oppose each other
  - supports: beliefs that provide evidence for another
  - refines: beliefs that clarify or improve another
  - depends_on: beliefs that require another to be true
  - related: beliefs that are semantically connected

  Detected by tracks which process identified the relationship.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @relationship_types ~w(contradicts supports refines depends_on related derived_from)
  @detected_by_types ~w(skeptic resonator manual inference)

  schema "belief_relationships" do
    field(:relationship_type, :string)
    field(:confidence, :float, default: 0.5)
    field(:detected_by, :string)
    field(:evidence, :string)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:source_belief, Lincoln.Beliefs.Belief)
    belongs_to(:target_belief, Lincoln.Beliefs.Belief)

    timestamps(type: :utc_datetime)
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :relationship_type,
      :confidence,
      :detected_by,
      :evidence,
      :agent_id,
      :source_belief_id,
      :target_belief_id
    ])
    |> validate_required([:relationship_type, :agent_id, :source_belief_id, :target_belief_id])
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_inclusion(:detected_by, @detected_by_types ++ [nil])
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> unique_constraint([:source_belief_id, :target_belief_id, :relationship_type],
      name: :belief_relationships_unique_idx
    )
  end
end
