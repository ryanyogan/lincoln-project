defmodule Lincoln.Repo.Migrations.CreateActions do
  use Ecto.Migration

  def change do
    create table(:actions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tool_name, :string, null: false
      add :tool_server, :string, null: false
      add :arguments, :map, null: false, default: %{}

      add :risk_tier, :integer, null: false, default: 0
      add :reversibility, :string, null: false, default: "reversible"
      add :predicted_outcome, :string, size: 1024
      add :prediction_confidence, :float, null: false, default: 0.5

      add :status, :string, null: false, default: "proposed"
      add :result, :map
      add :error, :string, size: 2048
      add :executed_at, :utc_datetime

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false
      add :goal_id, references(:goals, type: :binary_id, on_delete: :nilify_all)
      add :observation_memory_id, references(:memories, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:actions, [:agent_id, :status])
    create index(:actions, [:agent_id, :risk_tier, :status])
    create index(:actions, [:goal_id])
  end
end
