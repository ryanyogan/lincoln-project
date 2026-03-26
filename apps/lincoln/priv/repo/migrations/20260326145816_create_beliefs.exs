defmodule Lincoln.Repo.Migrations.CreateBeliefs do
  use Ecto.Migration

  def change do
    # Enable pgvector extension
    execute("CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector")

    create table(:beliefs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)

      # Core belief content
      add(:statement, :text, null: false)
      # Short version for display
      add(:summary, :string)

      # Confidence and certainty (0.0 - 1.0)
      add(:confidence, :float, null: false, default: 0.5)

      # Entrenchment - how resistant to revision (higher = more entrenched)
      # Based on AGM framework: core beliefs are harder to revise
      add(:entrenchment, :integer, null: false, default: 1)

      # Source tracking - critical for "Lincoln Six Echo" moment
      # :training - from LLM training data (can't be directly verified)
      # :observation - directly observed/experienced
      # :inference - derived from other beliefs
      # :testimony - told by another agent/user
      add(:source_type, :string, null: false)

      # What evidence/experience led to this belief
      add(:source_evidence, :text)

      # Semantic embedding for similarity matching
      add(:embedding, :vector, size: 384)

      # Contradiction tracking
      add(:contradicted_at, :utc_datetime)
      add(:contradicted_by_id, references(:beliefs, type: :binary_id, on_delete: :nilify_all))

      # Status: active, superseded, retracted
      add(:status, :string, default: "active")

      # Revision tracking
      add(:revision_count, :integer, default: 0)
      add(:last_reinforced_at, :utc_datetime)
      add(:last_challenged_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:beliefs, [:agent_id]))
    create(index(:beliefs, [:status]))
    create(index(:beliefs, [:source_type]))
    create(index(:beliefs, [:confidence]))
    create(index(:beliefs, [:entrenchment]))
    create(index(:beliefs, [:contradicted_at]))

    # Vector similarity index for semantic search
    execute(
      "CREATE INDEX beliefs_embedding_idx ON beliefs USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX IF EXISTS beliefs_embedding_idx"
    )
  end
end
