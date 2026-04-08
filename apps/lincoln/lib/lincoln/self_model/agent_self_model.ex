defmodule Lincoln.SelfModel.AgentSelfModel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "self_model" do
    field(:total_thoughts, :integer, default: 0)
    field(:completed_thoughts, :integer, default: 0)
    field(:failed_thoughts, :integer, default: 0)
    field(:interrupted_thoughts, :integer, default: 0)
    field(:local_tier_count, :integer, default: 0)
    field(:ollama_tier_count, :integer, default: 0)
    field(:claude_tier_count, :integer, default: 0)
    field(:dominant_topics, {:array, :string}, default: [])
    field(:contradiction_detections, :integer, default: 0)
    field(:cascade_detections, :integer, default: 0)
    field(:narrative_count, :integer, default: 0)
    field(:total_ticks, :integer, default: 0)
    field(:self_summary, :string)
    field(:last_updated_at, :utc_datetime)
    belongs_to(:agent, Lincoln.Agents.Agent)
    timestamps(type: :utc_datetime)
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [
      :total_thoughts,
      :completed_thoughts,
      :failed_thoughts,
      :interrupted_thoughts,
      :local_tier_count,
      :ollama_tier_count,
      :claude_tier_count,
      :dominant_topics,
      :contradiction_detections,
      :cascade_detections,
      :narrative_count,
      :total_ticks,
      :self_summary,
      :last_updated_at,
      :agent_id
    ])
    |> validate_required([:agent_id])
    |> unique_constraint(:agent_id)
  end
end
