defmodule Lincoln.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    # Conversations table - chat sessions with an agent
    create table(:conversations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:title, :string)
      add(:started_at, :utc_datetime)
      add(:last_message_at, :utc_datetime)
      add(:message_count, :integer, default: 0)

      timestamps(type: :utc_datetime)
    end

    create(index(:conversations, [:agent_id]))
    create(index(:conversations, [:last_message_at]))

    # Messages table - individual messages in a conversation
    create table(:messages, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :conversation_id,
        references(:conversations, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:role, :string, null: false)
      add(:content, :text, null: false)

      # Cognitive metadata (for Lincoln's responses)
      add(:memories_retrieved, :integer, default: 0)
      add(:beliefs_consulted, :integer, default: 0)
      add(:beliefs_formed, :integer, default: 0)
      add(:beliefs_revised, :integer, default: 0)
      add(:questions_generated, :integer, default: 0)
      add(:contradiction_detected, :boolean, default: false)
      add(:thinking_summary, :text)

      # Baseline comparison (optional)
      add(:baseline_response, :text)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create(index(:messages, [:conversation_id]))
    create(index(:messages, [:inserted_at]))
  end
end
