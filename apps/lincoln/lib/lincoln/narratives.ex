defmodule Lincoln.Narratives do
  @moduledoc """
  Lincoln's autobiographical narrative reflections.

  Every N substrate ticks, Lincoln generates a short self-reflection
  about what it has been thinking about and learning. Over time, these
  accumulate into an autobiography — the story of how Lincoln changed.

  In the divergence demo, two Lincolns with different attention parameters
  write different autobiographies from the same starting point.
  """

  import Ecto.Query
  alias Lincoln.Narratives.NarrativeReflection
  alias Lincoln.Repo

  @doc "Create a new narrative reflection for an agent."
  def create_reflection(agent_id, attrs) when is_binary(agent_id) do
    %NarrativeReflection{}
    |> NarrativeReflection.changeset(Map.put(attrs, :agent_id, agent_id))
    |> Repo.insert()
  end

  @doc "List narrative reflections for an agent, newest first."
  def list_reflections(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    NarrativeReflection
    |> where([r], r.agent_id == ^agent_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Get the most recent narrative reflection for an agent."
  def latest_reflection(agent_id) do
    NarrativeReflection
    |> where([r], r.agent_id == ^agent_id)
    |> order_by([r], desc: r.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Count total narrative reflections for an agent."
  def count_reflections(agent_id) do
    NarrativeReflection
    |> where([r], r.agent_id == ^agent_id)
    |> Repo.aggregate(:count)
  end
end
