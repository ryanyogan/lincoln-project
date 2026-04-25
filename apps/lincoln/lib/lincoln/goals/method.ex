defmodule Lincoln.Goals.Method do
  @moduledoc """
  A reusable goal-decomposition method — an HTN-style template that says
  "for goals shaped like this, here are the sub-goals to create."

  Methods are agent-scoped and keyed by the embedding of their pattern
  string, so the decomposer can find a similar prior method by vector
  similarity instead of having to re-ask the LLM every time.

  `sub_goal_templates` is a list of maps:

      [
        %{"statement" => "Find the form", "priority" => 8},
        %{"statement" => "Fill it out", "priority" => 7},
        %{"statement" => "Submit it", "priority" => 9}
      ]

  Origin values:

    * `"llm"` — produced by `Lincoln.Goals.Decomposer` from an LLM call
    * `"user"` — written by hand
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @origins ~w(llm user)

  schema "goal_methods" do
    field :pattern, :string
    field :description, :string
    field :embedding, Pgvector.Ecto.Vector
    field :sub_goal_templates, {:array, :map}, default: []
    field :usage_count, :integer, default: 0
    field :success_count, :integer, default: 0
    field :failure_count, :integer, default: 0
    field :origin, :string, default: "llm"
    field :last_used_at, :utc_datetime

    belongs_to :agent, Lincoln.Agents.Agent

    timestamps(type: :utc_datetime)
  end

  def origins, do: @origins

  def create_changeset(method, attrs, agent_id) do
    method
    |> cast(attrs, [
      :pattern,
      :description,
      :embedding,
      :sub_goal_templates,
      :origin
    ])
    |> put_change(:agent_id, agent_id)
    |> validate_required([:pattern, :sub_goal_templates])
    |> validate_inclusion(:origin, @origins)
  end

  def usage_changeset(method, outcome) when outcome in [:success, :failure] do
    field = if outcome == :success, do: :success_count, else: :failure_count

    method
    |> change(%{
      usage_count: method.usage_count + 1,
      last_used_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> change(Map.put(%{}, field, Map.get(method, field) + 1))
  end

  @doc "Computed success rate; returns 0.0 if never used."
  def success_rate(%__MODULE__{usage_count: 0}), do: 0.0

  def success_rate(%__MODULE__{success_count: s, usage_count: u}),
    do: s / u
end
