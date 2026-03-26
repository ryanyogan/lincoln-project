defmodule Lincoln.Repo.Migrations.CreateActionLog do
  use Ecto.Migration

  def change do
    create table(:action_log, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)

      # What action was taken
      add(:action_type, :string, null: false)

      # Action details
      add(:description, :text)
      add(:parameters, :map, default: %{})

      # Semantic embedding for pattern detection
      add(:embedding, :vector, size: 384)

      # Semantic hash for quick loop detection
      add(:semantic_hash, :string)

      # Outcome tracking
      # success, failure, pending
      add(:outcome, :string)
      add(:outcome_details, :text)

      # Context
      # user, schedule, curiosity, reflection
      add(:triggered_by, :string)
      add(:context, :map, default: %{})

      # Related entities
      add(:related_question_id, :binary_id)
      add(:related_belief_id, :binary_id)
      add(:related_memory_id, :binary_id)

      timestamps(type: :utc_datetime)
    end

    create(index(:action_log, [:agent_id]))
    create(index(:action_log, [:action_type]))
    create(index(:action_log, [:semantic_hash]))
    create(index(:action_log, [:outcome]))
    create(index(:action_log, [:inserted_at]))

    # Vector similarity index for pattern detection
    execute(
      "CREATE INDEX action_log_embedding_idx ON action_log USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX IF EXISTS action_log_embedding_idx"
    )
  end
end
