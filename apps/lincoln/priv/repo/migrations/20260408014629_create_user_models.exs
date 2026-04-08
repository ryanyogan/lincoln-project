defmodule Lincoln.Repo.Migrations.CreateUserModels do
  use Ecto.Migration

  def change do
    create table(:user_models, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:session_id, :string, null: false)
      add(:message_count, :integer, default: 0)
      add(:question_count, :integer, default: 0)
      add(:topics, {:array, :string}, default: [])
      add(:vocabulary_style, :string, default: "unknown")
      add(:first_seen_at, :utc_datetime)
      add(:last_seen_at, :utc_datetime)
      add(:model_data, :map, default: %{})
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:user_models, [:agent_id, :session_id]))
    create(index(:user_models, [:agent_id]))
  end
end
