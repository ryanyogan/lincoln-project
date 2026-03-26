defmodule Lincoln.Repo.Migrations.CreateBeliefRevisions do
  use Ecto.Migration

  def change do
    create table(:belief_revisions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:belief_id, references(:beliefs, type: :binary_id, on_delete: :delete_all), null: false)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)

      # What changed
      add(:previous_statement, :text)
      add(:previous_confidence, :float)
      add(:new_confidence, :float)

      # Why it changed - critical for understanding belief dynamics
      # :strengthened - new evidence supporting the belief
      # :weakened - evidence contradicting but not enough to retract
      # :retracted - belief no longer held
      # :superseded - replaced by a more accurate belief
      # :contracted - removed due to consistency maintenance (AGM contraction)
      add(:revision_type, :string, null: false)

      # What triggered the revision
      # observation, inference, contradiction, decay
      add(:trigger_type, :string)
      add(:trigger_evidence, :text)
      # Optional reference to triggering memory
      add(:trigger_memory_id, :binary_id)

      # Reasoning behind the revision
      add(:reasoning, :text)

      timestamps(type: :utc_datetime)
    end

    create(index(:belief_revisions, [:belief_id]))
    create(index(:belief_revisions, [:agent_id]))
    create(index(:belief_revisions, [:revision_type]))
    create(index(:belief_revisions, [:inserted_at]))
  end
end
