defmodule Lincoln.MCP.SearchCache do
  @moduledoc """
  ETS-backed query cache with rate limiting for search adapters.

  Reads hit the public ETS table directly (no GenServer bottleneck).
  The GenServer owns the table and handles periodic cleanup of expired
  entries.

  ## Rate limiting

  A simple token-bucket tracks searches per minute. When the limit is
  hit, `rate_limited?/0` returns `true` and callers should short-circuit
  (return cached results or `{:ok, []}`).

  ## Cache keys

  Queries are normalized (downcased, trimmed) and hashed with
  `:erlang.phash2/1` for fast, fixed-size keys.
  """

  use GenServer

  require Logger

  @table :lincoln_search_cache
  @ttl_seconds 3600
  @max_searches_per_minute 10
  @cleanup_interval_ms :timer.minutes(10)

  # ── Client API ──────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Look up a cached result. Returns `{:ok, results}` or `:miss`."
  @spec get(String.t()) :: {:ok, list()} | :miss
  def get(query) do
    key = cache_key(query)

    case :ets.lookup(@table, key) do
      [{^key, results, inserted_at}] ->
        if System.os_time(:second) - inserted_at < @ttl_seconds do
          bump_counter(:hits)
          {:ok, results}
        else
          :ets.delete(@table, key)
          bump_counter(:misses)
          :miss
        end

      [] ->
        bump_counter(:misses)
        :miss
    end
  end

  @doc "Store results in the cache."
  @spec put(String.t(), list()) :: :ok
  def put(query, results) do
    key = cache_key(query)
    :ets.insert(@table, {key, results, System.os_time(:second)})
    :ok
  end

  @doc "Returns cache statistics."
  @spec stats() :: %{
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          cached: non_neg_integer(),
          rate_limited: non_neg_integer()
        }
  def stats do
    cached =
      case :ets.info(@table, :size) do
        :undefined -> 0
        n -> max(0, n - 3)
      end

    %{
      hits: read_counter(:hits),
      misses: read_counter(:misses),
      cached: cached,
      rate_limited: read_counter(:rate_limited)
    }
  end

  @doc "Check whether the per-minute rate limit has been hit."
  @spec rate_limited?() :: boolean()
  def rate_limited? do
    now = System.os_time(:second)

    case :ets.lookup(@table, :rate_bucket) do
      [{:rate_bucket, count, window_start}] ->
        if now - window_start >= 60 do
          # Window expired — reset
          :ets.insert(@table, {:rate_bucket, 0, now})
          false
        else
          if count >= @max_searches_per_minute do
            bump_counter(:rate_limited)
            true
          else
            :ets.insert(@table, {:rate_bucket, count + 1, window_start})
            false
          end
        end

      [] ->
        :ets.insert(@table, {:rate_bucket, 1, now})
        false
    end
  end

  # ── GenServer callbacks ─────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    # Seed counters
    :ets.insert(table, {:hits, 0})
    :ets.insert(table, {:misses, 0})
    :ets.insert(table, {:rate_limited, 0})

    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    expire_old_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  # ── Helpers ─────────────────────────────────────────────────────────

  defp cache_key(query) do
    query
    |> String.trim()
    |> String.downcase()
    |> :erlang.phash2()
  end

  defp expire_old_entries do
    now = System.os_time(:second)
    # Walk the table and delete expired cache entries (skip meta keys)
    :ets.foldl(
      fn
        {key, _results, inserted_at}, acc when is_integer(key) ->
          if now - inserted_at >= @ttl_seconds, do: :ets.delete(@table, key)
          acc

        _other, acc ->
          acc
      end,
      :ok,
      @table
    )
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp bump_counter(name) do
    :ets.update_counter(@table, name, {2, 1}, {name, 0})
  rescue
    ArgumentError -> :ok
  end

  defp read_counter(name) do
    case :ets.lookup(@table, name) do
      [{^name, count}] -> count
      _ -> 0
    end
  rescue
    ArgumentError -> 0
  end
end
