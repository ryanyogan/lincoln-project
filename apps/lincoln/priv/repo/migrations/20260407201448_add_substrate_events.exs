defmodule Lincoln.Repo.Migrations.AddSubstrateEvents do
  use Ecto.Migration

  def change do
    create table(:substrate_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:agent_id, :binary_id, null: false)
      add(:event_type, :string, null: false)
      add(:event_data, :map)
      add(:tick_number, :integer, default: 0)
      add(:attention_score, :float)
      add(:inference_tier, :string, default: "local")

      timestamps(type: :utc_datetime)
    end

    create(index(:substrate_events, [:agent_id]))
    create(index(:substrate_events, [:agent_id, :inserted_at]))
  end
end
