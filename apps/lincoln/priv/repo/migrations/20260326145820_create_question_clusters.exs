defmodule Lincoln.Repo.Migrations.CreateQuestionClusters do
  use Ecto.Migration

  def change do
    create table(:question_clusters, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)

      # Cluster description
      # What this cluster is about
      add(:theme, :string, null: false)
      add(:description, :text)

      # Centroid embedding for the cluster
      add(:centroid_embedding, :vector, size: 384)

      # Statistics
      add(:question_count, :integer, default: 0)

      # Status
      # active, resolved, merged
      add(:status, :string, default: "active")

      timestamps(type: :utc_datetime)
    end

    create(index(:question_clusters, [:agent_id]))
    create(index(:question_clusters, [:status]))

    # Now add the foreign key from questions to clusters
    alter table(:questions) do
      modify(
        :cluster_id,
        references(:question_clusters, type: :binary_id, on_delete: :nilify_all)
      )
    end
  end
end
