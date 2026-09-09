defmodule Lincoln.Repo.Migrations.CreatePredictionErrors do
  use Ecto.Migration

  def change do
    create table(:prediction_errors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
      add :thought_id, :string, null: false
      add :impulse_source, :string
      add :belief_id, :binary_id
      add :thought_type, :string
      add :tier, :string
      add :topic_cluster, :string

      add :expected_score, :float, null: false
      add :actual_outcome, :float, null: false
      add :prediction_error, :float, null: false

      add :beliefs_created, :integer, default: 0
      add :beliefs_revised, :integer, default: 0
      add :beliefs_retracted, :integer, default: 0
      add :relationships_created, :integer, default: 0
      add :questions_resolved, :integer, default: 0
      add :goals_advanced, :integer, default: 0
      add :findings_created, :integer, default: 0

      add :thought_duration_ms, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:prediction_errors, [:agent_id, :inserted_at])
    create index(:prediction_errors, [:agent_id, :impulse_source])
  end
end
