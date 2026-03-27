defmodule Lincoln.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:type, :string, null: false)
      # low, medium, high, critical
      add(:severity, :string)
      add(:context, :map, default: %{})
      add(:duration_ms, :integer)
      add(:related_topic, :string)
      add(:related_code, :string)
      add(:metadata, :map, default: %{})

      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:conversation_id, references(:conversations, type: :binary_id, on_delete: :nilify_all))

      timestamps()
    end

    create(index(:events, [:agent_id, :type]))
    create(index(:events, [:agent_id, :inserted_at]))
    create(index(:events, [:type, :inserted_at]))
  end
end
