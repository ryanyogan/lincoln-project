defmodule Lincoln.Repo.Migrations.CreateNarrativeReflections do
  use Ecto.Migration

  def change do
    create table(:narrative_reflections, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:content, :string, null: false)
      add(:tick_number, :integer, default: 0)
      add(:period_start_tick, :integer, default: 0)
      add(:period_end_tick, :integer, default: 0)
      add(:belief_count, :integer, default: 0)
      add(:thought_count, :integer, default: 0)
      add(:dominant_topics, {:array, :string}, default: [])
      timestamps(type: :utc_datetime)
    end

    create(index(:narrative_reflections, [:agent_id]))
    create(index(:narrative_reflections, [:agent_id, :tick_number]))
  end
end
