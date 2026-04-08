defmodule Lincoln.Narratives.NarrativeReflection do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "narrative_reflections" do
    field(:content, :string)
    field(:tick_number, :integer, default: 0)
    field(:period_start_tick, :integer, default: 0)
    field(:period_end_tick, :integer, default: 0)
    field(:belief_count, :integer, default: 0)
    field(:thought_count, :integer, default: 0)
    field(:dominant_topics, {:array, :string}, default: [])
    belongs_to(:agent, Lincoln.Agents.Agent)
    timestamps(type: :utc_datetime)
  end

  def changeset(reflection, attrs) do
    reflection
    |> cast(attrs, [
      :content,
      :tick_number,
      :period_start_tick,
      :period_end_tick,
      :belief_count,
      :thought_count,
      :dominant_topics,
      :agent_id
    ])
    |> validate_required([:content, :agent_id])
  end
end
