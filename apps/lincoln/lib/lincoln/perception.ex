defmodule Lincoln.Perception do
  @moduledoc """
  Perception is Lincoln's sensory layer — the entry point for signals from the
  outside world (file inboxes, RSS feeds, API endpoints, web searches) into the
  cognitive substrate.

  Architecture:

      ┌──────────┐     ┌──────────┐     ┌────────────┐     ┌──────────┐
      │  Source  │ ──▶ │  Ingest  │ ──▶ │  Salience  │ ──▶ │  Memory  │
      └──────────┘     └──────────┘     └────────────┘     └──────────┘

  Sources are long-running processes under `Lincoln.Perception.Supervisor` that
  hand `RawObservation` structs to `ingest/2`. Salience decides whether the
  observation is kept and at what importance. Kept observations are persisted
  as memories of type `"observation"` — they do not directly create beliefs.

  This module is the only public surface. Sources should not write to
  `Lincoln.Memory` directly so that the salience filter and source-context
  enrichment remain in one place.
  """

  alias Lincoln.{Agents, Memory}
  alias Lincoln.Perception.{RawObservation, Salience}

  require Logger

  @type ingest_result ::
          {:ok, Memory.Memory.t()}
          | {:filtered, reason :: atom()}
          | {:error, term()}

  @doc """
  Run a raw observation through salience and persist it as an observation memory
  if it survives.

  Returns:
    * `{:ok, memory}` — observation was salient, memory created
    * `{:filtered, reason}` — observation was filtered (empty/duplicate/etc.)
    * `{:error, reason}` — persistence failure

  Options are forwarded to `Salience.score/3` (e.g. `:embeddings` for adapter
  override).
  """
  @spec ingest(Agents.Agent.t(), RawObservation.t(), keyword()) :: ingest_result()
  def ingest(%Agents.Agent{} = agent, %RawObservation{} = obs, opts \\ []) do
    case Salience.score(agent, obs, opts) do
      {:filter, reason} ->
        Logger.debug(fn ->
          "[Perception] Filtered observation from #{obs.source}: #{reason}"
        end)

        {:filtered, reason}

      {:keep, importance, embedding} ->
        persist(agent, obs, importance, embedding)
    end
  end

  defp persist(agent, obs, importance, embedding) do
    attrs = %{
      content: obs.content,
      memory_type: "observation",
      importance: importance,
      embedding: embedding,
      source_context:
        Map.merge(obs.metadata || %{}, %{
          "source" => obs.source,
          "title" => obs.title,
          "url" => obs.url,
          "external_id" => obs.external_id,
          "trust_weight" => obs.trust_weight,
          "occurred_at" => occurred_at_iso(obs.occurred_at)
        })
    }

    case Memory.create_memory(agent, attrs) do
      {:ok, _memory} = ok ->
        Logger.info(fn ->
          "[Perception] Ingested observation from #{obs.source} (importance #{importance})"
        end)

        :telemetry.execute(
          [:lincoln, :perception, :ingested],
          %{importance: importance},
          %{agent_id: agent.id, source: obs.source}
        )

        ok

      {:error, _changeset} = err ->
        err
    end
  end

  defp occurred_at_iso(nil), do: nil
  defp occurred_at_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
end
