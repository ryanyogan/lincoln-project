defmodule Lincoln.Repo.Migrations.CreateInterests do
  use Ecto.Migration

  def change do
    create table(:interests, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)

      # What the agent is curious about
      add(:topic, :string, null: false)
      add(:description, :text)

      # Semantic embedding for matching
      add(:embedding, :vector, size: 384)

      # Interest level (affects how much attention to pay)
      # 0.0 - 1.0
      add(:intensity, :float, default: 0.5)

      # Origin of interest
      # :emergent - developed naturally from experiences
      # :assigned - given by user/system
      # :derived - from another interest or belief
      add(:origin_type, :string, null: false)

      # Activity tracking
      add(:last_explored_at, :utc_datetime)
      add(:exploration_count, :integer, default: 0)

      # Status
      # active, satisfied, dormant
      add(:status, :string, default: "active")

      timestamps(type: :utc_datetime)
    end

    create(index(:interests, [:agent_id]))
    create(index(:interests, [:status]))
    create(index(:interests, [:intensity]))

    # Vector similarity index
    execute(
      "CREATE INDEX interests_embedding_idx ON interests USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX IF EXISTS interests_embedding_idx"
    )
  end
end
