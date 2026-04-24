defmodule Lincoln.Repo.Migrations.CreateGoals do
  use Ecto.Migration

  def change do
    create table(:goals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :statement, :string, null: false, size: 1024
      add :status, :string, null: false, default: "active"
      add :priority, :integer, null: false, default: 5
      add :deadline, :utc_datetime
      add :origin, :string, null: false, default: "user"
      add :success_criteria, :map, null: false, default: %{}
      add :embedding, :vector, size: 384
      add :progress_estimate, :float, null: false, default: 0.0
      add :last_evaluated_at, :utc_datetime

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      add :parent_goal_id,
          references(:goals, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create index(:goals, [:agent_id, :status])
    create index(:goals, [:agent_id, :priority])
    create index(:goals, [:parent_goal_id])
  end
end
