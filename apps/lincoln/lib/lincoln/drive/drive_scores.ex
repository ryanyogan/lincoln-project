defmodule Lincoln.Drive.DriveScores do
  @moduledoc """
  Computes drive adjustments from prediction error history.

  Each impulse type's average prediction error becomes a score adjustment:
  positive PE → boost (this kind of thinking has been productive),
  negative PE → dampen (this kind of thinking has been boring).

  Uses exponential decay so recent experience dominates.
  """

  alias Lincoln.Drive

  @default_window_hours 24
  @default_decay_rate 0.95
  @default_max_adjustment 0.15
  @default_floor -0.10

  def impulse_drive_adjustments(agent_id, opts \\ []) do
    window_hours = Keyword.get(opts, :window_hours, @default_window_hours)
    decay_rate = Keyword.get(opts, :decay_rate, @default_decay_rate)
    max_adjustment = Keyword.get(opts, :max_adjustment, @default_max_adjustment)
    floor = Keyword.get(opts, :floor, @default_floor)

    since = DateTime.add(DateTime.utc_now(), -window_hours * 3600, :second)
    errors = Drive.list_recent_errors(agent_id, since: since, limit: 500)

    errors
    |> Enum.group_by(& &1.impulse_source)
    |> Enum.reject(fn {source, _} -> is_nil(source) end)
    |> Enum.map(fn {source, group} ->
      weighted_mean = exponential_weighted_mean(group, decay_rate)
      adjustment = clamp(weighted_mean * 0.5, floor, max_adjustment)
      {source, adjustment}
    end)
    |> Map.new()
  rescue
    _ -> %{}
  end

  defp exponential_weighted_mean([], _decay_rate), do: 0.0

  defp exponential_weighted_mean(errors, decay_rate) do
    now = DateTime.utc_now()

    {weighted_sum, weight_total} =
      Enum.reduce(errors, {0.0, 0.0}, fn error, {sum, total} ->
        age_hours = DateTime.diff(now, error.inserted_at, :second) / 3600.0
        weight = :math.pow(decay_rate, age_hours)
        {sum + error.prediction_error * weight, total + weight}
      end)

    if weight_total > 0.0, do: weighted_sum / weight_total, else: 0.0
  end

  defp clamp(value, floor, ceiling) do
    value |> max(floor) |> min(ceiling)
  end
end
