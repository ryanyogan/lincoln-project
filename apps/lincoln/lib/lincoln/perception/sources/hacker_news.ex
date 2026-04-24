defmodule Lincoln.Perception.Sources.HackerNews do
  @moduledoc """
  Polls the public Hacker News Algolia search API for top stories and ingests
  each as a `Lincoln.Perception.RawObservation`.

  This is a low-trust source (default 0.5) — Lincoln should not form
  high-confidence beliefs from individual HN headlines. Salience-level dedup
  prevents the same story being ingested twice in a single window. The
  Algolia API ranks "front_page" stories by recency × score, which is a
  reasonable signal-to-noise filter for a substrate's first sensory feed.

  Configuration:

      {Lincoln.Perception.Sources.HackerNews,
       [interval_ms: 30 * 60_000, trust_weight: 0.5, agent_id: nil, hits: 15]}

  The HTTP layer is overridable via the `:http` option for tests; the default
  uses `Req`. A failed poll is logged and retried on the next interval — the
  GenServer never crashes on transient network errors.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Perception}
  alias Lincoln.Perception.RawObservation

  @behaviour Lincoln.Perception.Source

  @default_interval_ms 30 * 60_000
  @default_trust_weight 0.5
  @default_hits 15
  @api_url "https://hn.algolia.com/api/v1/search"

  defstruct [
    :agent_id,
    :trust_weight,
    :interval_ms,
    :hits,
    :http,
    :timer_ref
  ]

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @impl Lincoln.Perception.Source
  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:name] || :default},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc "Force an immediate poll cycle. Mostly useful in tests."
  def poll_now(server \\ __MODULE__), do: GenServer.cast(server, :poll)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      agent_id: Keyword.get(opts, :agent_id),
      trust_weight: Keyword.get(opts, :trust_weight, @default_trust_weight),
      interval_ms: Keyword.get(opts, :interval_ms, @default_interval_ms),
      hits: Keyword.get(opts, :hits, @default_hits),
      http: Keyword.get(opts, :http, &default_get/1)
    }

    # First poll on a short delay so the rest of the boot sequence completes.
    timer = Process.send_after(self(), :poll, 5_000)
    {:ok, %{state | timer_ref: timer}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    do_poll(state)
    timer = Process.send_after(self(), :poll, state.interval_ms)
    {:noreply, %{state | timer_ref: timer}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast(:poll, state) do
    do_poll(state)
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Polling
  # ---------------------------------------------------------------------------

  defp do_poll(state) do
    with {:ok, agent} <- resolve_agent(state.agent_id),
         {:ok, hits} <- fetch_hits(state) do
      Enum.each(hits, fn hit -> ingest_hit(agent, state, hit) end)
      Logger.info("[Perception.HackerNews] Polled #{length(hits)} stories")
    else
      {:error, reason} ->
        Logger.warning("[Perception.HackerNews] Poll failed: #{inspect(reason)}")
    end
  end

  defp fetch_hits(state) do
    url = "#{@api_url}?tags=front_page&hitsPerPage=#{state.hits}"

    case state.http.(url) do
      {:ok, %{"hits" => hits}} when is_list(hits) -> {:ok, hits}
      {:ok, body} -> {:error, {:unexpected_body, body}}
      {:error, _} = err -> err
    end
  end

  defp default_get(url) do
    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} when is_map(body) -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ingest_hit(agent, state, hit) do
    obs =
      RawObservation.new("rss:hn", build_content(hit),
        title: hit["title"],
        url: hit["url"] || "https://news.ycombinator.com/item?id=#{hit["objectID"]}",
        external_id: "hn:#{hit["objectID"]}",
        trust_weight: state.trust_weight,
        occurred_at: parse_created_at(hit),
        metadata: %{
          "points" => hit["points"],
          "num_comments" => hit["num_comments"],
          "author" => hit["author"]
        }
      )

    _ = Perception.ingest(agent, obs)
  end

  defp build_content(hit) do
    parts =
      [hit["title"], hit["story_text"]]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))

    Enum.join(parts, "\n\n")
  end

  defp parse_created_at(%{"created_at" => iso}) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_created_at(_), do: DateTime.utc_now()

  defp resolve_agent(nil) do
    case Agents.get_or_create_default_agent() do
      {:ok, agent} -> {:ok, agent}
      agent when is_map(agent) -> {:ok, agent}
      err -> err
    end
  end

  defp resolve_agent(agent_id) do
    case Agents.get_agent(agent_id) do
      nil -> {:error, :agent_not_found}
      agent -> {:ok, agent}
    end
  end
end
