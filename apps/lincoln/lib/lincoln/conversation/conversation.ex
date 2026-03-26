defmodule Lincoln.Conversation.Conversation do
  @moduledoc """
  Schema for a conversation session.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "conversations" do
    field(:title, :string)
    field(:started_at, :utc_datetime)
    field(:last_message_at, :utc_datetime)
    field(:message_count, :integer, default: 0)

    belongs_to(:agent, Lincoln.Agents.Agent)
    has_many(:messages, Lincoln.Conversation.Message)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :started_at, :last_message_at, :message_count, :agent_id])
    |> validate_required([:agent_id])
  end
end
