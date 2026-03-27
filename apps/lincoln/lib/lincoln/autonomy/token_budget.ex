defmodule Lincoln.Autonomy.TokenBudget do
  @moduledoc """
  Token budget management for autonomous learning.

  Tracks API usage and prevents runaway costs.
  Lincoln learns efficiently - wide breadth, not deep token consumption.
  """

  alias Lincoln.Autonomy

  # Default budget limits
  @default_hourly_limit 50_000
  @default_session_limit 500_000

  # Cost estimates (per 1M tokens, approximate)
  @input_cost_per_million 3.0
  @output_cost_per_million 15.0

  # ============================================================================
  # Budget Checking
  # ============================================================================

  @doc """
  Checks if the session has budget remaining.
  """
  def has_budget?(session) do
    session_limit = get_session_limit(session)
    session.tokens_used < session_limit
  end

  @doc """
  Gets remaining tokens in budget.
  """
  def remaining_tokens(session) do
    session_limit = get_session_limit(session)
    max(0, session_limit - session.tokens_used)
  end

  @doc """
  Checks if a proposed operation fits in budget.
  """
  def can_afford?(session, estimated_tokens) do
    remaining_tokens(session) >= estimated_tokens
  end

  @doc """
  Gets the session's budget configuration.
  """
  def get_session_limit(session) do
    session.config["token_limit"] || @default_session_limit
  end

  @doc """
  Gets hourly limit for rate control.
  """
  def get_hourly_limit(session) do
    session.config["hourly_limit"] || @default_hourly_limit
  end

  # ============================================================================
  # Usage Tracking
  # ============================================================================

  @doc """
  Records token usage for an operation.
  """
  def record_usage(session, tokens) do
    Autonomy.increment_session(session, :tokens_used, tokens)
    Autonomy.increment_session(session, :api_calls_made, 1)
  end

  @doc """
  Checks hourly rate and warns if approaching limit.
  """
  def check_hourly_rate(session) do
    # Get logs from last hour
    recent_logs = Autonomy.list_logs(session, limit: 500)

    one_hour_ago = DateTime.add(DateTime.utc_now(), -3600, :second)

    hourly_tokens =
      recent_logs
      |> Enum.filter(fn log ->
        DateTime.compare(log.inserted_at, one_hour_ago) == :gt
      end)
      |> Enum.map(& &1.tokens_used)
      |> Enum.sum()

    hourly_limit = get_hourly_limit(session)

    cond do
      hourly_tokens >= hourly_limit ->
        {:exceeded, hourly_tokens, hourly_limit}

      hourly_tokens >= hourly_limit * 0.8 ->
        {:warning, hourly_tokens, hourly_limit}

      true ->
        {:ok, hourly_tokens, hourly_limit}
    end
  end

  # ============================================================================
  # Cost Estimation
  # ============================================================================

  @doc """
  Estimates token count for a text string.
  Rough approximation: ~4 characters per token.
  """
  def estimate_tokens(text) when is_binary(text) do
    div(String.length(text), 4)
  end

  def estimate_tokens(_), do: 0

  @doc """
  Estimates tokens for a research operation.
  """
  def estimate_research_tokens do
    # Typical research cycle:
    # - Summarization input: ~2000 tokens
    # - Summarization output: ~200 tokens
    # - Fact extraction input: ~500 tokens
    # - Fact extraction output: ~100 tokens
    # - Topic discovery: ~100 tokens
    2000 + 200 + 500 + 100 + 100
  end

  @doc """
  Estimates tokens for a reflection operation.
  """
  def estimate_reflection_tokens do
    # Reflection typically uses more context
    3000
  end

  @doc """
  Estimates tokens for a code evolution operation.
  """
  def estimate_evolution_tokens do
    # Code analysis and generation
    5000
  end

  @doc """
  Calculates estimated cost in USD.
  """
  def estimate_cost(tokens) do
    # Assume 70% input, 30% output ratio
    input_tokens = tokens * 0.7
    output_tokens = tokens * 0.3

    input_cost = input_tokens / 1_000_000 * @input_cost_per_million
    output_cost = output_tokens / 1_000_000 * @output_cost_per_million

    Float.round(input_cost + output_cost, 4)
  end

  @doc """
  Formats cost as a string.
  """
  def format_cost(tokens) do
    cost = estimate_cost(tokens)

    cond do
      cost < 0.01 -> "<$0.01"
      cost < 1.0 -> "$#{Float.round(cost, 2)}"
      true -> "$#{Float.round(cost, 2)}"
    end
  end

  # ============================================================================
  # Budget Strategies
  # ============================================================================

  @doc """
  Suggests whether to do expensive operations based on budget state.
  """
  def suggest_operation_type(session) do
    remaining = remaining_tokens(session)
    session_limit = get_session_limit(session)
    percentage_remaining = remaining / session_limit * 100

    cond do
      percentage_remaining > 80 ->
        # Plenty of budget - can do anything
        :full

      percentage_remaining > 50 ->
        # Moderate budget - skip expensive operations occasionally
        :moderate

      percentage_remaining > 20 ->
        # Low budget - only essential operations
        :conservative

      true ->
        # Very low - wind down
        :minimal
    end
  end

  @doc """
  Returns true if we should skip expensive operations.
  """
  def should_skip_expensive?(session) do
    suggest_operation_type(session) in [:conservative, :minimal]
  end

  @doc """
  Returns true if we should consider stopping.
  """
  def should_wind_down?(session) do
    suggest_operation_type(session) == :minimal
  end
end
