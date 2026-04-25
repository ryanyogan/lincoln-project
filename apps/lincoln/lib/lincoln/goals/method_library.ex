defmodule Lincoln.Goals.MethodLibrary do
  @moduledoc """
  Stores and retrieves goal decomposition methods.

  Methods are keyed by the embedding of their pattern string. The library
  uses pgvector cosine similarity to find a prior method that fits a new
  goal, so common goal shapes only require one LLM call ever.

  Access pattern:

      iex> Library.find_similar(agent, embedding, threshold: 0.85)
      %Method{...}        # reuse it

      iex> Library.record(agent, "submit_form", templates, embedding)
      {:ok, method}        # save it for next time

      iex> Library.record_usage(method, :success)
      {:ok, updated}       # outcome feedback
  """

  alias Lincoln.Agents.Agent
  alias Lincoln.Goals.Method
  alias Lincoln.Repo

  import Ecto.Query

  @default_similarity 0.85

  @doc """
  Find the most-similar stored method for the given embedding, or `nil`
  if nothing crosses the similarity threshold.
  """
  def find_similar(%Agent{id: agent_id}, embedding, opts \\ []) when is_list(embedding) do
    threshold = Keyword.get(opts, :threshold, @default_similarity)
    {:ok, agent_id_binary} = Ecto.UUID.dump(agent_id)

    sql = """
    SELECT m.*, 1 - (m.embedding <=> $1::vector) AS similarity
    FROM goal_methods m
    WHERE m.agent_id = $2
      AND m.embedding IS NOT NULL
      AND 1 - (m.embedding <=> $1::vector) >= $3
    ORDER BY similarity DESC
    LIMIT 1
    """

    case Repo.query!(sql, [embedding, agent_id_binary, threshold]) do
      %{rows: []} ->
        nil

      %{columns: cols, rows: [row]} ->
        cols
        |> Enum.map(&String.to_atom/1)
        |> Enum.zip(row)
        |> Map.new()
        |> hydrate()
    end
  end

  @doc """
  Persist a new method. Pattern must be unique per agent in spirit
  (similar patterns are deduped at lookup time, not at insert time).
  """
  def record(%Agent{id: agent_id}, pattern, templates, embedding, opts \\ [])
      when is_binary(pattern) and is_list(templates) do
    %Method{}
    |> Method.create_changeset(
      %{
        pattern: pattern,
        description: Keyword.get(opts, :description),
        sub_goal_templates: templates,
        embedding: embedding,
        origin: Keyword.get(opts, :origin, "llm")
      },
      agent_id
    )
    |> Repo.insert()
  end

  @doc "Increments usage counters when a method's outcome becomes known."
  def record_usage(%Method{} = method, outcome) when outcome in [:success, :failure] do
    method
    |> Method.usage_changeset(outcome)
    |> Repo.update()
  end

  @doc """
  Returns the agent's library, ordered by recent usage. Useful for the UI
  and for debugging the calibration of decomposition.
  """
  def list_methods(%Agent{id: agent_id}) do
    Method
    |> where([m], m.agent_id == ^agent_id)
    |> order_by([m], desc_nulls_last: m.last_used_at, desc: m.inserted_at)
    |> Repo.all()
  end

  defp hydrate(map) do
    map = Map.put_new(map, :__struct__, Method)

    map
    |> normalize_uuid(:id)
    |> normalize_uuid(:agent_id)
    |> Map.delete(:similarity)
    |> then(&struct(Method, Map.delete(&1, :__struct__)))
  end

  defp normalize_uuid(map, key) do
    case Map.get(map, key) do
      <<_::binary-size(16)>> = bin ->
        {:ok, str} = Ecto.UUID.load(bin)
        Map.put(map, key, str)

      _ ->
        map
    end
  end
end
