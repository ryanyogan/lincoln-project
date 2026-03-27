defmodule Lincoln.Events.Cache do
  @moduledoc """
  ETS-backed event cache for fast pattern analysis.
  Keeps recent events in memory for quick querying without hitting the database.
  """

  use GenServer
  require Logger

  @table :lincoln_events_cache
  @max_events_per_agent 1000
  @cleanup_interval :timer.minutes(5)

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Store an event in the cache"
  def store(event) do
    GenServer.cast(__MODULE__, {:store, event})
  end

  @doc "Get recent events for an agent"
  def recent(agent_id, opts \\ []) do
    type = Keyword.get(opts, :type)
    limit = Keyword.get(opts, :limit, 100)

    match_spec =
      if type do
        [{{agent_id, :_, type, :_}, [], [:"$_"]}]
      else
        [{{agent_id, :_, :_, :_}, [], [:"$_"]}]
      end

    @table
    |> :ets.select(match_spec)
    |> Enum.sort_by(fn {_, timestamp, _, _} -> timestamp end, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(fn {_, _, _, event} -> event end)
  end

  @doc "Count events of a type since a given time"
  def count_since(agent_id, type, since) do
    since_unix = DateTime.to_unix(since, :millisecond)

    @table
    |> :ets.select([{{agent_id, :"$1", type, :_}, [{:>=, :"$1", since_unix}], [true]}])
    |> length()
  end

  @doc "Check if a pattern exists (e.g., repeated failures)"
  def pattern_exists?(agent_id, type, count, window_minutes) do
    since = DateTime.add(DateTime.utc_now(), -window_minutes, :minute)
    count_since(agent_id, type, since) >= count
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :bag, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:store, event}, state) do
    # Convert NaiveDateTime to unix timestamp (Ecto uses NaiveDateTime by default)
    timestamp = naive_to_unix(event.inserted_at)
    :ets.insert(@table, {event.agent_id, timestamp, event.type, event})
    {:noreply, state}
  end

  # Convert NaiveDateTime or DateTime to unix milliseconds
  defp naive_to_unix(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix(:millisecond)
  end

  defp naive_to_unix(%DateTime{} = dt) do
    DateTime.to_unix(dt, :millisecond)
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_old_events()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_old_events do
    # Remove events older than 1 hour from cache (they're still in DB)
    cutoff = DateTime.to_unix(DateTime.add(DateTime.utc_now(), -1, :hour), :millisecond)

    # Get all agent IDs
    agent_ids =
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {agent_id, _, _, _} -> agent_id end)
      |> Enum.uniq()

    # For each agent, keep only the most recent @max_events_per_agent events
    Enum.each(agent_ids, fn agent_id ->
      events =
        @table
        |> :ets.select([{{agent_id, :_, :_, :_}, [], [:"$_"]}])
        |> Enum.sort_by(fn {_, ts, _, _} -> ts end, :desc)

      # Delete old events beyond the limit
      events
      |> Enum.drop(@max_events_per_agent)
      |> Enum.each(fn entry -> :ets.delete_object(@table, entry) end)

      # Delete events older than cutoff
      :ets.select_delete(@table, [{{agent_id, :"$1", :_, :_}, [{:<, :"$1", cutoff}], [true]}])
    end)

    Logger.debug("Event cache cleanup completed")
  end
end
