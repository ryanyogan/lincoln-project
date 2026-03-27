defmodule Lincoln.Events.Event do
  @moduledoc """
  Schema for events - the core of Lincoln's self-awareness system.

  Events capture significant moments during Lincoln's operation, from thought loops
  and knowledge gaps to successful improvements. This enables pattern detection
  and self-improvement over time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lincoln.Agents.Agent
  alias Lincoln.Conversation.Conversation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(
    thought_loop_gave_up
    thought_loop_slow
    low_confidence_response
    user_correction
    knowledge_gap_detected
    belief_contradiction
    research_failed
    belief_formed
    belief_revised
    error_occurred
    slow_operation
    improvement_opportunity
    code_change_applied
    improvement_observed
  )

  @severities ~w(low medium high critical)

  schema "events" do
    field(:type, :string)
    field(:severity, :string, default: "medium")
    field(:context, :map, default: %{})
    field(:duration_ms, :integer)
    field(:related_topic, :string)
    field(:related_code, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:agent, Agent)
    belongs_to(:conversation, Conversation)

    timestamps()
  end

  def event_types, do: @event_types
  def severities, do: @severities

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :type,
      :severity,
      :context,
      :duration_ms,
      :related_topic,
      :related_code,
      :metadata,
      :agent_id,
      :conversation_id
    ])
    |> validate_required([:type, :agent_id])
    |> validate_inclusion(:type, @event_types)
    |> validate_inclusion(:severity, @severities)
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:conversation_id)
  end
end
