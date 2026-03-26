defmodule Lincoln.Repo.Migrations.CreateFindings do
  use Ecto.Migration

  def change do
    create table(:findings, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:question_id, references(:questions, type: :binary_id, on_delete: :nilify_all))

      # Finding content
      add(:answer, :text, null: false)
      add(:summary, :string)

      # How the finding was obtained
      # :investigation - actively researched
      # :serendipity - discovered while doing something else
      # :testimony - told by user/another agent
      # :inference - derived from existing knowledge
      add(:source_type, :string, null: false)

      # Evidence and confidence
      # What supports this finding
      add(:evidence, :text)
      add(:confidence, :float, default: 0.5)

      # Semantic embedding
      add(:embedding, :vector, size: 384)

      # Did this finding create/modify a belief?
      add(:resulted_in_belief_id, :binary_id)

      # Verification status
      add(:verified, :boolean, default: false)
      add(:verified_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:findings, [:agent_id]))
    create(index(:findings, [:question_id]))
    create(index(:findings, [:source_type]))
    create(index(:findings, [:confidence]))

    # Update questions to reference findings
    alter table(:questions) do
      modify(
        :resolved_by_finding_id,
        references(:findings, type: :binary_id, on_delete: :nilify_all)
      )
    end

    # Vector similarity index
    execute(
      "CREATE INDEX findings_embedding_idx ON findings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100)",
      "DROP INDEX IF EXISTS findings_embedding_idx"
    )
  end
end
