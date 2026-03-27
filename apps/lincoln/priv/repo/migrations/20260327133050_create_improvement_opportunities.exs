defmodule Lincoln.Repo.Migrations.CreateImprovementOpportunities do
  use Ecto.Migration

  def change do
    create table(:improvement_opportunities, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      # pending, in_progress, completed, failed, abandoned
      add(:status, :string, default: "pending", null: false)
      add(:priority, :integer, default: 5)
      # what pattern triggered this
      add(:pattern, :string, null: false)
      # file or module to look at
      add(:suggested_focus, :string)
      add(:analysis, :map, default: %{})
      add(:attempted_at, :utc_datetime)
      add(:completed_at, :utc_datetime)
      # improved, no_change, degraded
      add(:outcome, :string)

      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:trigger_event_id, references(:events, type: :binary_id, on_delete: :nilify_all))
      add(:code_change_id, references(:code_changes, type: :binary_id, on_delete: :nilify_all))

      timestamps()
    end

    create(index(:improvement_opportunities, [:agent_id, :status]))
    create(index(:improvement_opportunities, [:agent_id, :priority]))
  end
end
