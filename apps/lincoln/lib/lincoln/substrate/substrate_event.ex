defmodule Lincoln.Substrate.SubstrateEvent do
  @moduledoc """
  Schema for recording substrate events in the trajectory log.

  Each row captures one discrete event in an agent's cognitive processing —
  ticks, focus changes, event processing, etc.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "substrate_events" do
    field(:agent_id, :binary_id)
    field(:event_type, :string)
    field(:event_data, :map)
    field(:tick_number, :integer, default: 0)
    field(:attention_score, :float)
    field(:inference_tier, :string, default: "local")

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :agent_id,
      :event_type,
      :event_data,
      :tick_number,
      :attention_score,
      :inference_tier
    ])
    |> validate_required([:agent_id, :event_type])
  end
end
