defmodule Lincoln.Repo.Migrations.CreateAutonomyTables do
  use Ecto.Migration

  def change do
    # Learning sessions - tracks autonomous learning periods
    create table(:learning_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:status, :string, null: false, default: "pending")
      add(:started_at, :utc_datetime)
      add(:stopped_at, :utc_datetime)
      add(:topics_explored, :integer, default: 0)
      add(:beliefs_formed, :integer, default: 0)
      add(:memories_created, :integer, default: 0)
      add(:code_changes_made, :integer, default: 0)
      add(:api_calls_made, :integer, default: 0)
      add(:tokens_used, :integer, default: 0)
      add(:config, :map, default: %{})
      add(:seed_topics, {:array, :string}, default: [])
      add(:reflection_notes, :text)
      timestamps(type: :utc_datetime)
    end

    create(index(:learning_sessions, [:agent_id]))
    create(index(:learning_sessions, [:status]))
    create(index(:learning_sessions, [:started_at]))

    # Research topics - queue of things to learn
    create table(:research_topics, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:session_id, references(:learning_sessions, type: :binary_id, on_delete: :delete_all))
      add(:topic, :string, null: false)
      add(:source, :string, null: false, default: "discovered")
      add(:priority, :integer, default: 5)
      add(:status, :string, null: false, default: "pending")

      add(
        :parent_topic_id,
        references(:research_topics, type: :binary_id, on_delete: :nilify_all)
      )

      add(:depth, :integer, default: 0)
      add(:context, :text)
      add(:started_at, :utc_datetime)
      add(:completed_at, :utc_datetime)
      add(:facts_extracted, :integer, default: 0)
      add(:beliefs_formed, :integer, default: 0)
      add(:child_topics_discovered, :integer, default: 0)
      add(:error_message, :text)
      timestamps(type: :utc_datetime)
    end

    create(index(:research_topics, [:agent_id]))
    create(index(:research_topics, [:session_id]))
    create(index(:research_topics, [:status]))
    create(index(:research_topics, [:priority]))
    create(index(:research_topics, [:parent_topic_id]))

    # Web sources - pages Lincoln has read
    create table(:web_sources, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:topic_id, references(:research_topics, type: :binary_id, on_delete: :nilify_all))
      add(:session_id, references(:learning_sessions, type: :binary_id, on_delete: :nilify_all))
      add(:url, :string, null: false)
      add(:title, :string)
      add(:domain, :string)
      add(:content_summary, :text)
      add(:content_length, :integer)
      add(:facts_extracted, :integer, default: 0)
      add(:quality_score, :float)
      add(:fetch_status, :string, default: "success")
      add(:error_message, :text)
      add(:fetched_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end

    create(index(:web_sources, [:agent_id]))
    create(index(:web_sources, [:topic_id]))
    create(index(:web_sources, [:session_id]))
    create(index(:web_sources, [:domain]))
    create(unique_index(:web_sources, [:agent_id, :url]))

    # Code changes - Lincoln's self-modifications
    create table(:code_changes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:session_id, references(:learning_sessions, type: :binary_id, on_delete: :nilify_all))
      add(:file_path, :string, null: false)
      add(:change_type, :string, null: false)
      add(:description, :text, null: false)
      add(:reasoning, :text, null: false)
      add(:original_content, :text)
      add(:new_content, :text)
      add(:diff, :text)
      add(:status, :string, default: "applied")
      add(:git_commit, :string)
      add(:applied_at, :utc_datetime)
      add(:committed_at, :utc_datetime)
      timestamps(type: :utc_datetime)
    end

    create(index(:code_changes, [:agent_id]))
    create(index(:code_changes, [:session_id]))
    create(index(:code_changes, [:file_path]))
    create(index(:code_changes, [:status]))

    # Learning logs - detailed activity stream
    create table(:learning_logs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:session_id, references(:learning_sessions, type: :binary_id, on_delete: :delete_all))
      add(:topic_id, references(:research_topics, type: :binary_id, on_delete: :nilify_all))
      add(:activity_type, :string, null: false)
      add(:description, :text, null: false)
      add(:details, :map, default: %{})
      add(:tokens_used, :integer, default: 0)
      add(:duration_ms, :integer)
      timestamps(type: :utc_datetime)
    end

    create(index(:learning_logs, [:agent_id]))
    create(index(:learning_logs, [:session_id]))
    create(index(:learning_logs, [:topic_id]))
    create(index(:learning_logs, [:activity_type]))
    create(index(:learning_logs, [:inserted_at]))
  end
end
