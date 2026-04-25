defmodule Lincoln.Actions.Action do
  @moduledoc """
  An action Lincoln may take in the world via an MCP tool.

  Actions are first-class entities — they encode the tool to call, the
  predicted outcome, the prediction confidence (which downstream calibration
  compares against the actual result), risk tier, and reversibility. Status
  moves through a small lifecycle:

      proposed ─▶ executing ─▶ executed
                            │
                            └▶ failed

      proposed ─▶ pending_approval (tier 2 — Phase 7)
      proposed ─▶ skipped          (dry-run for tier 3, future)

  Risk tiers (Phase 5 enforces this policy in `Lincoln.Actions.executable?/1`):

    * 0 — local & reversible (e.g. write a file in a sandbox dir) → autonomous
    * 1 — external & reversible (e.g. draft a Slack message, calendar read) →
          autonomous + audited
    * 2 — external & irreversible → requires explicit user approval (Phase 7)
    * 3 — high-stakes → dry-run only until calibration is proven (future)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(proposed pending_approval executing executed failed skipped)
  @reversibilities ~w(reversible irreversible destructive)
  @risk_tiers 0..3

  schema "actions" do
    field :tool_name, :string
    field :tool_server, :string
    field :arguments, :map, default: %{}

    field :risk_tier, :integer, default: 0
    field :reversibility, :string, default: "reversible"
    field :predicted_outcome, :string
    field :prediction_confidence, :float, default: 0.5

    field :status, :string, default: "proposed"
    field :result, :map
    field :error, :string
    field :executed_at, :utc_datetime

    belongs_to :agent, Lincoln.Agents.Agent
    belongs_to :goal, Lincoln.Goals.Goal
    belongs_to :observation_memory, Lincoln.Memory.Memory

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def reversibilities, do: @reversibilities
  def risk_tiers, do: Enum.to_list(@risk_tiers)

  @doc """
  Changeset for creating a proposed action.
  """
  def create_changeset(action, attrs, agent_id) do
    action
    |> cast(attrs, [
      :tool_name,
      :tool_server,
      :arguments,
      :risk_tier,
      :reversibility,
      :predicted_outcome,
      :prediction_confidence,
      :status,
      :goal_id
    ])
    |> put_change(:agent_id, agent_id)
    |> validate_required([:tool_name, :tool_server])
    |> validate_inclusion(:risk_tier, Enum.to_list(@risk_tiers))
    |> validate_inclusion(:reversibility, @reversibilities)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:prediction_confidence,
      greater_than_or_equal_to: 0.0,
      less_than_or_equal_to: 1.0
    )
  end

  @doc "Changeset for transitioning the action lifecycle."
  def transition_changeset(action, attrs) do
    action
    |> cast(attrs, [:status, :result, :error, :executed_at, :observation_memory_id])
    |> validate_inclusion(:status, @statuses)
  end
end
