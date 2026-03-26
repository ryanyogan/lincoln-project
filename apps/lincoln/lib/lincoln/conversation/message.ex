defmodule Lincoln.Conversation.Message do
  @moduledoc """
  Schema for an individual message in a conversation.

  Includes cognitive metadata for Lincoln's responses:
  - memories_retrieved: How many memories were consulted
  - beliefs_consulted: How many beliefs were checked
  - beliefs_formed: New beliefs created from this exchange
  - beliefs_revised: Existing beliefs that were updated
  - questions_generated: New questions Lincoln asked itself
  - contradiction_detected: Whether a contradiction was found
  - thinking_summary: Brief summary of cognitive process
  - baseline_response: Raw Claude response for comparison
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field(:role, :string)
    field(:content, :string)

    # Cognitive metadata
    field(:memories_retrieved, :integer, default: 0)
    field(:beliefs_consulted, :integer, default: 0)
    field(:beliefs_formed, :integer, default: 0)
    field(:beliefs_revised, :integer, default: 0)
    field(:questions_generated, :integer, default: 0)
    field(:contradiction_detected, :boolean, default: false)
    field(:thinking_summary, :string)

    # Baseline comparison
    field(:baseline_response, :string)

    belongs_to(:conversation, Lincoln.Conversation.Conversation)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :role,
      :content,
      :conversation_id,
      :memories_retrieved,
      :beliefs_consulted,
      :beliefs_formed,
      :beliefs_revised,
      :questions_generated,
      :contradiction_detected,
      :thinking_summary,
      :baseline_response
    ])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
