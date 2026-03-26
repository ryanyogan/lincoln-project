defmodule Lincoln.Beliefs.BeliefRevision do
  @moduledoc """
  Schema for tracking belief revisions over time.

  This implements part of the AGM belief revision framework:
  - Expansion: adding a new belief
  - Contraction: removing a belief to maintain consistency
  - Revision: adding a belief that contradicts existing beliefs

  Understanding why beliefs change is critical for:
  1. Debugging agent behavior
  2. Detecting cognitive patterns
  3. The "Lincoln Six Echo" moment - recognizing epistemic limitations
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @revision_types ~w(strengthened weakened retracted superseded contracted)
  @trigger_types ~w(observation inference contradiction decay reflection)

  schema "belief_revisions" do
    field(:previous_statement, :string)
    field(:previous_confidence, :float)
    field(:new_confidence, :float)
    field(:revision_type, :string)
    field(:trigger_type, :string)
    field(:trigger_evidence, :string)
    field(:trigger_memory_id, :binary_id)
    field(:reasoning, :string)

    belongs_to(:belief, Lincoln.Beliefs.Belief)
    belongs_to(:agent, Lincoln.Agents.Agent)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(revision, attrs) do
    revision
    |> cast(attrs, [
      :previous_statement,
      :previous_confidence,
      :new_confidence,
      :revision_type,
      :trigger_type,
      :trigger_evidence,
      :trigger_memory_id,
      :reasoning
    ])
    |> validate_required([:revision_type])
    |> validate_inclusion(:revision_type, @revision_types)
    |> validate_inclusion(:trigger_type, @trigger_types)
  end

  @doc """
  Changeset for creating a revision record.
  """
  def create_changeset(revision, attrs, belief, agent_id) do
    revision
    |> changeset(attrs)
    |> put_change(:belief_id, belief.id)
    |> put_change(:agent_id, agent_id)
    |> put_change(:previous_statement, belief.statement)
    |> put_change(:previous_confidence, belief.confidence)
  end
end
