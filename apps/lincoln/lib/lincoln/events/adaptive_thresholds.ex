defmodule Lincoln.Events.AdaptiveThresholds do
  @moduledoc """
  Adaptive thresholds for Lincoln's self-awareness.
  All thresholds are learned from Lincoln's own history - no hardcoded constants.

  "Slow" = slower than MY typical performance
  "Frequent" = more often than MY typical rate
  """

  alias Lincoln.Repo
  import Ecto.Query

  # Default values used only when there's no history
  @default_response_time_ms 5000
  @default_slow_multiplier 2.0
  @default_observation_hours 24

  @doc """
  Check if an operation duration is considered slow for this agent.
  Slow = above the 90th percentile of historical durations.
  """
  def slow?(agent, operation_type, duration_ms) do
    threshold = get_slow_threshold(agent, operation_type)
    duration_ms > threshold
  end

  @doc """
  Get the threshold for "slow" operations.
  Returns the 90th percentile of historical durations, or default if no history.
  """
  def get_slow_threshold(agent, operation_type) do
    # Get recent durations for this operation type
    durations = get_recent_durations(agent, operation_type, 100)

    case durations do
      [] ->
        @default_response_time_ms * @default_slow_multiplier

      durations ->
        # Calculate 90th percentile
        sorted = Enum.sort(durations)
        index = floor(length(sorted) * 0.9)
        Enum.at(sorted, index) || @default_response_time_ms * @default_slow_multiplier
    end
  end

  @doc """
  Check if an event type is occurring more frequently than normal.
  """
  def frequent?(agent, event_type, count, window_minutes) do
    baseline = get_baseline_rate(agent, event_type, window_minutes)
    count > baseline * 1.5
  end

  @doc """
  Get the baseline rate for an event type (average count per window).
  """
  def get_baseline_rate(agent, event_type, window_minutes) do
    # Look at the last 7 days of data
    seven_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)

    # Count events per window over the historical period
    query =
      from(e in Lincoln.Events.Event,
        where: e.agent_id == ^agent.id,
        where: e.type == ^to_string(event_type),
        where: e.inserted_at >= ^seven_days_ago,
        select: count(e.id)
      )

    total_count = Repo.one(query) || 0

    # Calculate average per window
    windows_in_7_days = 7 * 24 * 60 / window_minutes

    if windows_in_7_days > 0 do
      total_count / windows_in_7_days
    else
      0
    end
  end

  @doc """
  Determine how long to observe after a code change before evaluating outcome.
  Based on the type and scope of the change.
  """
  def observation_period(change_type, impact_scope, agent) do
    # Try to get learned period from history
    learned = get_learned_observation_period(agent, change_type, impact_scope)

    if learned do
      learned
    else
      # Default based on impact
      case impact_scope do
        :minimal -> hours_to_seconds(1)
        :moderate -> hours_to_seconds(6)
        :significant -> hours_to_seconds(24)
        :major -> hours_to_seconds(72)
        _ -> hours_to_seconds(@default_observation_hours)
      end
    end
  end

  @doc """
  Estimate the impact scope of a code change.
  """
  def estimate_impact_scope(file_path, description) do
    description_lower = String.downcase(description || "")

    cond do
      # Documentation changes are minimal impact
      String.contains?(description_lower, ["comment", "doc", "typo"]) ->
        :minimal

      # Core cognitive modules are significant
      String.contains?(file_path, ["thought_loop", "belief_formation", "conversation_handler"]) ->
        :significant

      # Worker changes are moderate
      String.contains?(file_path, ["worker"]) ->
        :moderate

      # Adding new features is major
      String.contains?(description_lower, ["add", "new", "feature", "implement"]) ->
        :major

      # Refactoring is moderate
      String.contains?(description_lower, ["refactor", "clean", "reorganize"]) ->
        :moderate

      # Default to moderate
      true ->
        :moderate
    end
  end

  @doc """
  Recalibrate thresholds based on recent data.
  Called periodically to keep thresholds current.
  """
  def recalibrate(_agent) do
    # This could store calibrated values in ETS or agent metadata
    # For now, we compute on-demand
    :ok
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp get_recent_durations(agent, operation_type, limit) do
    query =
      from(e in Lincoln.Events.Event,
        where: e.agent_id == ^agent.id,
        where: e.type == ^to_string(operation_type),
        where: not is_nil(e.duration_ms),
        order_by: [desc: e.inserted_at],
        limit: ^limit,
        select: e.duration_ms
      )

    Repo.all(query)
  end

  defp get_learned_observation_period(agent, _change_type, _impact_scope) do
    # Look at past improvements with similar characteristics
    query =
      from(io in Lincoln.Events.ImprovementOpportunity,
        where: io.agent_id == ^agent.id,
        where: io.status == "completed",
        where: not is_nil(io.completed_at) and not is_nil(io.attempted_at),
        order_by: [desc: io.completed_at],
        limit: 10
      )

    past_improvements = Repo.all(query)

    # Calculate average observation period from successful past improvements
    periods =
      past_improvements
      |> Enum.filter(fn io -> io.outcome == "improved" end)
      |> Enum.map(fn io ->
        DateTime.diff(io.completed_at, io.attempted_at, :second)
      end)
      |> Enum.filter(fn p -> p > 0 end)

    case periods do
      [] -> nil
      periods -> (Enum.sum(periods) / length(periods)) |> round()
    end
  end

  defp hours_to_seconds(hours), do: hours * 60 * 60
end
