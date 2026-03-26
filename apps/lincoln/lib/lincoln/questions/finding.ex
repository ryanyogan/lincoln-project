defmodule Lincoln.Questions.Finding do
  @moduledoc """
  Schema for a finding - an answer to a question.

  Findings bridge questions and beliefs:
  - They answer questions
  - They may lead to new beliefs
  - They record how answers were obtained
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(investigation serendipity testimony inference)

  schema "findings" do
    field(:answer, :string)
    field(:summary, :string)
    field(:source_type, :string)
    field(:evidence, :string)
    field(:confidence, :float, default: 0.5)
    field(:embedding, Pgvector.Ecto.Vector)
    field(:resulted_in_belief_id, :binary_id)
    field(:verified, :boolean, default: false)
    field(:verified_at, :utc_datetime)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:question, Lincoln.Questions.Question)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(finding, attrs) do
    finding
    |> cast(attrs, [
      :answer,
      :summary,
      :source_type,
      :evidence,
      :confidence,
      :embedding,
      :resulted_in_belief_id,
      :verified
    ])
    |> validate_required([:answer, :source_type])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_number(:confidence, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end

  @doc """
  Changeset for creating a finding.
  """
  def create_changeset(finding, attrs, agent_id, question_id \\ nil) do
    finding
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
    |> put_change(:question_id, question_id)
  end

  @doc """
  Changeset for verifying a finding.
  """
  def verify_changeset(finding) do
    change(finding,
      verified: true,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
  end
end
