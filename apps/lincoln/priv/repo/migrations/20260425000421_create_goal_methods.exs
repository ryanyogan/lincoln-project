defmodule Lincoln.Repo.Migrations.CreateGoalMethods do
  use Ecto.Migration

  def change do
    create table(:goal_methods, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :pattern, :string, null: false, size: 255
      add :description, :string, size: 1024
      add :embedding, :vector, size: 384
      add :sub_goal_templates, {:array, :map}, null: false, default: []
      add :usage_count, :integer, null: false, default: 0
      add :success_count, :integer, null: false, default: 0
      add :failure_count, :integer, null: false, default: 0
      add :origin, :string, null: false, default: "llm"
      add :last_used_at, :utc_datetime

      add :agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:goal_methods, [:agent_id])
  end
end
