defmodule Lincoln.Repo.Migrations.CreateSelfModel do
  use Ecto.Migration

  def change do
    create table(:self_model, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:total_thoughts, :integer, default: 0)
      add(:completed_thoughts, :integer, default: 0)
      add(:failed_thoughts, :integer, default: 0)
      add(:interrupted_thoughts, :integer, default: 0)
      add(:local_tier_count, :integer, default: 0)
      add(:ollama_tier_count, :integer, default: 0)
      add(:claude_tier_count, :integer, default: 0)
      add(:dominant_topics, {:array, :string}, default: [])
      add(:contradiction_detections, :integer, default: 0)
      add(:cascade_detections, :integer, default: 0)
      add(:narrative_count, :integer, default: 0)
      add(:total_ticks, :integer, default: 0)
      add(:self_summary, :string)
      add(:last_updated_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:self_model, [:agent_id]))
  end
end
