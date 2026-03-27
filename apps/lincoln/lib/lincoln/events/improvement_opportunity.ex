defmodule Lincoln.Events.ImprovementOpportunity do
  @moduledoc """
  Schema for improvement opportunities - actionable items for Lincoln's self-improvement.

  When pattern detection identifies a recurring struggle or failure mode, an improvement
  opportunity is created. Lincoln can then attempt to address it through code changes
  or other means, tracking the outcome to learn what works.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lincoln.Agents.Agent
  alias Lincoln.Events.Event
  alias Lincoln.Autonomy.CodeChange

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending in_progress completed failed abandoned)
  @outcomes ~w(improved no_change degraded)

  schema "improvement_opportunities" do
    field(:status, :string, default: "pending")
    field(:priority, :integer, default: 5)
    field(:pattern, :string)
    field(:suggested_focus, :string)
    field(:analysis, :map, default: %{})
    field(:attempted_at, :utc_datetime)
    field(:completed_at, :utc_datetime)
    field(:outcome, :string)

    belongs_to(:agent, Agent)
    belongs_to(:trigger_event, Event)
    belongs_to(:code_change, CodeChange)

    timestamps()
  end

  def statuses, do: @statuses
  def outcomes, do: @outcomes

  def changeset(opportunity, attrs) do
    opportunity
    |> cast(attrs, [
      :status,
      :priority,
      :pattern,
      :suggested_focus,
      :analysis,
      :attempted_at,
      :completed_at,
      :outcome,
      :agent_id,
      :trigger_event_id,
      :code_change_id
    ])
    |> validate_required([:pattern, :agent_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:outcome, @outcomes ++ [nil])
    |> validate_number(:priority, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:trigger_event_id)
    |> foreign_key_constraint(:code_change_id)
  end

  def mark_in_progress(opportunity) do
    change(opportunity, %{status: "in_progress", attempted_at: DateTime.utc_now()})
  end

  def mark_completed(opportunity, outcome) do
    change(opportunity, %{status: "completed", completed_at: DateTime.utc_now(), outcome: outcome})
  end

  def mark_failed(opportunity, _reason) do
    change(opportunity, %{status: "failed", completed_at: DateTime.utc_now()})
  end
end
