defmodule Lincoln.Drive.PredictionError do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @impulse_sources ~w(curiosity reflection learning investigation self_improve perception goal_pursuit action goal_review)

  schema "prediction_errors" do
    field :thought_id, :string
    field :impulse_source, :string
    field :belief_id, :binary_id
    field :thought_type, :string
    field :tier, :string
    field :topic_cluster, :string

    field :expected_score, :float
    field :actual_outcome, :float
    field :prediction_error, :float

    field :beliefs_created, :integer, default: 0
    field :beliefs_revised, :integer, default: 0
    field :beliefs_retracted, :integer, default: 0
    field :relationships_created, :integer, default: 0
    field :questions_resolved, :integer, default: 0
    field :goals_advanced, :integer, default: 0
    field :findings_created, :integer, default: 0

    field :thought_duration_ms, :integer

    belongs_to :agent, Lincoln.Agents.Agent

    timestamps(type: :utc_datetime)
  end

  def changeset(prediction_error, attrs) do
    prediction_error
    |> cast(attrs, [
      :agent_id,
      :thought_id,
      :impulse_source,
      :belief_id,
      :thought_type,
      :tier,
      :topic_cluster,
      :expected_score,
      :actual_outcome,
      :prediction_error,
      :beliefs_created,
      :beliefs_revised,
      :beliefs_retracted,
      :relationships_created,
      :questions_resolved,
      :goals_advanced,
      :findings_created,
      :thought_duration_ms
    ])
    |> validate_required([
      :agent_id,
      :thought_id,
      :expected_score,
      :actual_outcome,
      :prediction_error
    ])
    |> validate_number(:expected_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:actual_outcome, greater_than_or_equal_to: 0.0)
    |> validate_number(:prediction_error,
      greater_than_or_equal_to: -1.0,
      less_than_or_equal_to: 2.0
    )
    |> validate_inclusion(:impulse_source, @impulse_sources)
    |> foreign_key_constraint(:agent_id)
  end
end
