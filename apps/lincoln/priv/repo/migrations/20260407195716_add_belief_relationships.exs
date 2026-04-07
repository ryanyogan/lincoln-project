defmodule Lincoln.Repo.Migrations.AddBeliefRelationships do
  use Ecto.Migration

  def change do
    create table(:belief_relationships, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)

      add(:source_belief_id, references(:beliefs, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:target_belief_id, references(:beliefs, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:relationship_type, :string, null: false)
      add(:confidence, :float, default: 0.5)
      add(:detected_by, :string)
      add(:evidence, :text)

      timestamps(type: :utc_datetime)
    end

    create(index(:belief_relationships, [:agent_id]))
    create(index(:belief_relationships, [:source_belief_id]))
    create(index(:belief_relationships, [:target_belief_id]))

    create(
      unique_index(
        :belief_relationships,
        [:source_belief_id, :target_belief_id, :relationship_type],
        name: :belief_relationships_unique_idx
      )
    )
  end
end
