defmodule Lincoln.UserModels.UserModel do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_models" do
    field(:session_id, :string)
    field(:message_count, :integer, default: 0)
    field(:question_count, :integer, default: 0)
    field(:topics, {:array, :string}, default: [])
    field(:vocabulary_style, :string, default: "unknown")
    field(:first_seen_at, :utc_datetime)
    field(:last_seen_at, :utc_datetime)
    field(:model_data, :map, default: %{})
    belongs_to(:agent, Lincoln.Agents.Agent)
    timestamps(type: :utc_datetime)
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [
      :session_id,
      :message_count,
      :question_count,
      :topics,
      :vocabulary_style,
      :first_seen_at,
      :last_seen_at,
      :model_data,
      :agent_id
    ])
    |> validate_required([:session_id, :agent_id])
    |> validate_inclusion(:vocabulary_style, ["technical", "casual", "mixed", "unknown"])
    |> unique_constraint([:agent_id, :session_id])
  end
end
