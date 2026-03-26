defmodule Lincoln.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def change do
    create table(:memories, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)

      # Memory content
      add(:content, :text, null: false)
      # Short version for retrieval display
      add(:summary, :string)

      # Memory type classification
      # :observation - direct experience/perception
      # :reflection - higher-level insight from reflecting on memories
      # :conversation - interaction with user/other agents
      # :plan - intended action or goal
      add(:memory_type, :string, null: false)

      # Importance score (1-10) - affects retrieval priority
      add(:importance, :integer, null: false, default: 5)

      # Semantic embedding for similarity-based retrieval
      add(:embedding, :vector, size: 384)

      # Recency and access tracking (for retrieval scoring)
      add(:last_accessed_at, :utc_datetime)
      add(:access_count, :integer, default: 0)

      # Source context
      # Where/how memory was formed
      add(:source_context, :map, default: %{})

      # Links to related entities
      add(:related_belief_ids, {:array, :binary_id}, default: [])
      add(:related_question_id, :binary_id)

      timestamps(type: :utc_datetime)
    end

    create(index(:memories, [:agent_id]))
    create(index(:memories, [:memory_type]))
    create(index(:memories, [:importance]))
    create(index(:memories, [:last_accessed_at]))
    create(index(:memories, [:inserted_at]))

    # Vector similarity index
    execute(
      "CREATE INDEX memories_embedding_idx ON memories USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX IF EXISTS memories_embedding_idx"
    )
  end
end
