defmodule Lincoln.Drive do
  @moduledoc """
  Context module for the prediction error drive system.

  Records the gap between what attention predicted a thought would produce
  and what it actually produced. Over time, these signals shape which kinds
  of thinking Lincoln gravitates toward.
  """

  import Ecto.Query

  alias Lincoln.Drive.PredictionError
  alias Lincoln.Repo

  def record_prediction_error(agent_id, attrs) do
    %PredictionError{}
    |> PredictionError.changeset(Map.put(attrs, :agent_id, agent_id))
    |> Repo.insert()
  end

  def list_recent_errors(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since)
    impulse_source = Keyword.get(opts, :impulse_source)

    PredictionError
    |> where([pe], pe.agent_id == ^agent_id)
    |> maybe_filter_since(since)
    |> maybe_filter_impulse(impulse_source)
    |> order_by([pe], desc: pe.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def prune_old_errors(agent_id, opts \\ []) do
    hours = Keyword.get(opts, :hours, 72)
    cutoff = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    PredictionError
    |> where([pe], pe.agent_id == ^agent_id and pe.inserted_at < ^cutoff)
    |> Repo.delete_all()
  end

  defp maybe_filter_since(query, nil), do: query

  defp maybe_filter_since(query, %DateTime{} = since) do
    where(query, [pe], pe.inserted_at >= ^since)
  end

  defp maybe_filter_impulse(query, nil), do: query

  defp maybe_filter_impulse(query, source) do
    where(query, [pe], pe.impulse_source == ^source)
  end
end
