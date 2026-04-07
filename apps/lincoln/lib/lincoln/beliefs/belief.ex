defmodule Lincoln.Beliefs.Belief do
  @moduledoc """
  Schema for a belief - a statement the agent holds to be true.

  Beliefs are the core of the epistemic system. They have:
  - Confidence: how certain the agent is (0.0 - 1.0)
  - Entrenchment: how resistant to revision (AGM framework)
  - Source type: critical for distinguishing training vs experiential knowledge

  The "Lincoln Six Echo" moment occurs when an agent recognizes that
  beliefs from :training source can't be directly verified, while
  :observation beliefs come from direct experience.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(training observation inference testimony)
  @statuses ~w(active superseded retracted)

  schema "beliefs" do
    field(:statement, :string)
    field(:summary, :string)
    field(:confidence, :float, default: 0.5)
    field(:entrenchment, :integer, default: 1)
    field(:source_type, :string)
    field(:source_evidence, :string)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:contradicted_at, :utc_datetime)
    field(:status, :string, default: "active")
    field(:revision_count, :integer, default: 0)
    field(:last_reinforced_at, :utc_datetime)
    field(:last_challenged_at, :utc_datetime)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:contradicted_by, __MODULE__)

    has_many(:revisions, Lincoln.Beliefs.BeliefRevision)

    has_many(:outgoing_relationships, Lincoln.Beliefs.BeliefRelationship,
      foreign_key: :source_belief_id
    )

    has_many(:incoming_relationships, Lincoln.Beliefs.BeliefRelationship,
      foreign_key: :target_belief_id
    )

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(belief, attrs) do
    belief
    |> cast(attrs, [
      :statement,
      :summary,
      :confidence,
      :entrenchment,
      :source_type,
      :source_evidence,
      :embedding,
      :status,
      :contradicted_at,
      :contradicted_by_id,
      :last_reinforced_at,
      :last_challenged_at
    ])
    |> validate_required([:statement, :source_type])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:entrenchment, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
  end

  @doc """
  Changeset for creating a new belief.
  """
  def create_changeset(belief, attrs, agent_id) do
    belief
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
  end

  @doc """
  Changeset for revising a belief's confidence.
  """
  def revise_confidence_changeset(belief, new_confidence, _reason)
      when is_float(new_confidence) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changes =
      if new_confidence > belief.confidence do
        [confidence: new_confidence, last_reinforced_at: now]
      else
        [confidence: new_confidence, last_challenged_at: now]
      end

    change(belief, changes ++ [revision_count: belief.revision_count + 1])
  end

  @doc """
  Changeset for marking a belief as contradicted.
  """
  def contradict_changeset(belief, contradicting_belief_id) do
    change(belief,
      status: "superseded",
      contradicted_at: DateTime.utc_now() |> DateTime.truncate(:second),
      contradicted_by_id: contradicting_belief_id
    )
  end

  @doc """
  Changeset for retracting a belief.
  """
  def retract_changeset(belief) do
    change(belief, status: "retracted")
  end

  @doc """
  Returns true if the belief is from direct experience.
  """
  def experiential?(%__MODULE__{source_type: source_type}) do
    source_type in ["observation", "inference"]
  end

  @doc """
  Returns true if the belief is from external sources (training or testimony).
  """
  def external?(%__MODULE__{source_type: source_type}) do
    source_type in ["training", "testimony"]
  end
end
