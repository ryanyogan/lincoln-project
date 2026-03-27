defmodule Lincoln.Autonomy.CodeChange do
  @moduledoc """
  Schema for tracking Lincoln's self-modifications to code.

  Every change Lincoln makes to his own codebase is logged here,
  including the reasoning, the diff, and git commit information.
  This allows for full auditability and rollback capability.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @change_types ~w(create modify refactor delete improve)
  @statuses ~w(proposed applied committed rolled_back failed)

  schema "code_changes" do
    field(:file_path, :string)
    field(:change_type, :string)
    field(:description, :string)
    field(:reasoning, :string)
    field(:original_content, :string)
    field(:new_content, :string)
    field(:diff, :string)
    field(:status, :string, default: "applied")
    field(:git_commit, :string)
    field(:applied_at, :utc_datetime)
    field(:committed_at, :utc_datetime)

    belongs_to(:agent, Lincoln.Agents.Agent)
    belongs_to(:session, Lincoln.Autonomy.LearningSession)

    timestamps(type: :utc_datetime)
  end

  def changeset(change, attrs) do
    change
    |> cast(attrs, [
      :file_path,
      :change_type,
      :description,
      :reasoning,
      :original_content,
      :new_content,
      :diff,
      :status,
      :git_commit,
      :applied_at,
      :committed_at
    ])
    |> validate_required([:file_path, :change_type, :description, :reasoning])
    |> validate_inclusion(:change_type, @change_types)
    |> validate_inclusion(:status, @statuses)
  end

  def create_changeset(change, attrs, agent_id, session_id) do
    change
    |> changeset(attrs)
    |> put_change(:agent_id, agent_id)
    |> put_change(:session_id, session_id)
    |> put_change(:applied_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def commit_changeset(change, commit_hash) do
    change
    |> Ecto.Changeset.change(%{
      status: "committed",
      git_commit: commit_hash,
      committed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def rollback_changeset(change) do
    change
    |> Ecto.Changeset.change(%{status: "rolled_back"})
  end

  def fail_changeset(change, reason) do
    change
    |> Ecto.Changeset.change(%{
      status: "failed",
      reasoning: change.reasoning <> "\n\nFailed: #{reason}"
    })
  end
end
