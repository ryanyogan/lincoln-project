defmodule Lincoln.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)

      # Agent personality and behavior configuration
      add(:personality, :map, default: %{})

      # Agent state
      add(:status, :string, default: "active")
      add(:last_active_at, :utc_datetime)

      # Statistics
      add(:beliefs_count, :integer, default: 0)
      add(:memories_count, :integer, default: 0)
      add(:questions_asked_count, :integer, default: 0)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:agents, [:name]))
    create(index(:agents, [:status]))
  end
end
