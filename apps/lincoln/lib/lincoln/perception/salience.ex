defmodule Lincoln.Perception.Salience do
  @moduledoc """
  Decides whether a `Lincoln.Perception.RawObservation` becomes a persisted memory.

  Salience answers two questions:

    1. Is this observation worth remembering at all? (`:keep | :filter`)
    2. If so, how important is it? (1..10)

  This is the gatekeeper that prevents external feeds from poisoning the belief
  system with noise. It does NOT form beliefs — it only routes signals into the
  observation memory layer. Belief formation happens later, downstream, when an
  observation cluster crosses the existing learning/reflection thresholds.

  Filter heuristics (in order):

    * empty / whitespace content → `:filter`
    * exact-content duplicate of a recent memory → `:filter`
    * embedding similarity ≥ duplicate threshold → `:filter` (semantic dedupe)
    * otherwise → `:keep` with importance derived from source trust + content shape

  All thresholds and weights are pure module attributes so the filter can be
  tested without mocks.
  """

  alias Lincoln.{Agents, Memory, Repo}
  alias Lincoln.Memory.Memory, as: MemorySchema
  alias Lincoln.Perception.RawObservation

  import Ecto.Query

  @duplicate_similarity 0.95
  @recent_window_hours 24
  @recent_lookback_limit 50

  @type decision ::
          {:keep, importance :: 1..10, embedding :: [float()] | nil}
          | {:filter, reason :: atom()}

  @doc """
  Score a raw observation against the agent's recent memory state.

  Returns `{:keep, importance, embedding}` or `{:filter, reason}`.

  Options:
    * `:embeddings` — adapter override (defaults to configured adapter)
    * `:now` — clock override for tests (defaults to `DateTime.utc_now/0`)
  """
  @spec score(Agents.Agent.t(), RawObservation.t(), keyword()) :: decision()
  def score(%Agents.Agent{} = agent, %RawObservation{} = obs, opts \\ []) do
    cond do
      blank?(obs.content) ->
        {:filter, :empty}

      content_duplicate?(agent, obs) ->
        {:filter, :exact_duplicate}

      true ->
        score_with_embedding(agent, obs, opts)
    end
  end

  defp score_with_embedding(agent, obs, opts) do
    case generate_embedding(obs, opts) do
      {:ok, embedding} ->
        if semantic_duplicate?(agent, embedding) do
          {:filter, :semantic_duplicate}
        else
          {:keep, importance(obs), embedding}
        end

      _error ->
        # Embedding failure is non-fatal — keep without embedding so the source
        # remains useful even if the embedding service is down.
        {:keep, importance(obs), nil}
    end
  end

  defp blank?(nil), do: true
  defp blank?(content), do: String.trim(content) == ""

  defp content_duplicate?(agent, obs) do
    cutoff = DateTime.add(DateTime.utc_now(), -@recent_window_hours * 3600, :second)
    content = obs.content

    Repo.exists?(
      from(m in MemorySchema,
        where: m.agent_id == ^agent.id,
        where: m.memory_type == "observation",
        where: m.inserted_at >= ^cutoff,
        where: m.content == ^content
      )
    )
  end

  defp semantic_duplicate?(agent, embedding) do
    case Memory.find_similar_memories(agent, embedding,
           limit: @recent_lookback_limit,
           threshold: @duplicate_similarity
         ) do
      [] -> false
      [_ | _] -> true
    end
  rescue
    _ -> false
  end

  defp generate_embedding(obs, opts) do
    adapter = Keyword.get(opts, :embeddings) || embeddings_adapter()
    adapter.embed(obs.content, [])
  rescue
    _ -> {:error, :embedding_failed}
  end

  defp embeddings_adapter do
    Application.get_env(:lincoln, :embeddings_adapter, Lincoln.Adapters.Embeddings.PythonService)
  end

  # Importance derivation: source trust contributes the most, content length is
  # a weak secondary signal. Clamped to the 1..10 schema range.
  defp importance(%RawObservation{trust_weight: trust, content: content}) do
    base = 3 + round(trust * 6)
    length_bonus = if String.length(content) > 400, do: 1, else: 0
    clamp(base + length_bonus, 1, 10)
  end

  defp clamp(n, lo, hi), do: n |> max(lo) |> min(hi)
end
