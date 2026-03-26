defmodule Lincoln.Questions.ActionLog do
  @moduledoc """
  Schema for logging agent actions.

  The action log serves two purposes:
  1. Audit trail for debugging
  2. Pattern detection for loop prevention
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @outcomes ~w(success failure pending)
  @triggers ~w(user schedule curiosity reflection maintenance)

  schema "action_log" do
    field(:action_type, :string)
    field(:description, :string)
    field(:parameters, :map, default: %{})
    field(:embedding, Pgvector.Ecto.Vector)
    field(:semantic_hash, :string)
    field(:outcome, :string)
    field(:outcome_details, :string)
    field(:triggered_by, :string)
    field(:context, :map, default: %{})
    field(:related_question_id, :binary_id)
    field(:related_belief_id, :binary_id)
    field(:related_memory_id, :binary_id)

    belongs_to(:agent, Lincoln.Agents.Agent)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(action_log, attrs) do
    action_log
    |> cast(attrs, [
      :action_type,
      :description,
      :parameters,
      :embedding,
      :semantic_hash,
      :outcome,
      :outcome_details,
      :triggered_by,
      :context,
      :related_question_id,
      :related_belief_id,
      :related_memory_id
    ])
    |> validate_required([:action_type])
    |> validate_inclusion(:outcome, @outcomes)
    |> validate_inclusion(:triggered_by, @triggers)
  end

  @doc """
  Changeset for creating an action log entry.
  """
  def create_changeset(action_log, attrs, agent_id) do
    action_log
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
    |> put_change(:outcome, "pending")
  end

  @doc """
  Changeset for recording outcome.
  """
  def complete_changeset(action_log, outcome, details \\ nil) do
    change(action_log,
      outcome: outcome,
      outcome_details: details
    )
  end
end
