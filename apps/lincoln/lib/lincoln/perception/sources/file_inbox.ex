defmodule Lincoln.Perception.Sources.FileInbox do
  @moduledoc """
  Watches a directory for new or modified files and delivers their contents to
  `Lincoln.Perception` as observations.

  Drop a `.txt`, `.md`, or `.json` file in the watched directory and Lincoln
  notices it on the next event tick. This is the simplest, highest-signal
  sensory source: the user curates what shows up.

  Behaviour:

    * On file create/modify, the file is read, packaged as a
      `Lincoln.Perception.RawObservation`, and ingested.
    * Files are processed exactly once per content hash via
      `Lincoln.Perception.Salience` exact-duplicate detection.
    * Read failures and oversized files are logged at debug level and skipped —
      the watcher never crashes on a bad file.
    * Files larger than `:max_bytes` are skipped (default 256 KB).
    * The agent is resolved on every event so that a freshly-created default
      agent can pick up watched files without a restart.

  Configuration (per source instance, passed via `start_link/1` or supervisor):

      %{
        path: "/home/ryan/lincoln-inbox",
        agent_id: "..." | nil,           # nil = default agent
        trust_weight: 0.9,
        extensions: ["txt", "md", "json"],
        max_bytes: 262_144
      }
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Perception}
  alias Lincoln.Perception.RawObservation

  @behaviour Lincoln.Perception.Source

  @default_extensions ~w(txt md json)
  @default_max_bytes 262_144
  @default_trust_weight 0.9

  defstruct [
    :path,
    :agent_id,
    :trust_weight,
    :extensions,
    :max_bytes,
    :watcher_pid
  ]

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: name_for(opts))
  end

  @impl Lincoln.Perception.Source
  def child_spec(opts) do
    %{
      id: {__MODULE__, opts[:path] || :default},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  defp name_for(opts) do
    case opts[:name] do
      nil -> __MODULE__
      n -> n
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  def init(opts) do
    path = Keyword.fetch!(opts, :path) |> Path.expand()

    state = %__MODULE__{
      path: path,
      agent_id: Keyword.get(opts, :agent_id),
      trust_weight: Keyword.get(opts, :trust_weight, @default_trust_weight),
      extensions: Keyword.get(opts, :extensions, @default_extensions),
      max_bytes: Keyword.get(opts, :max_bytes, @default_max_bytes)
    }

    {:ok, state, {:continue, :start_watcher}}
  end

  @impl GenServer
  def handle_continue(:start_watcher, state) do
    case ensure_dir(state.path) do
      :ok ->
        case FileSystem.start_link(dirs: [state.path], name: nil) do
          {:ok, pid} ->
            FileSystem.subscribe(pid)

            Logger.info(
              "[Perception.FileInbox] Watching #{state.path} for #{Enum.join(state.extensions, ", ")} files"
            )

            {:noreply, %{state | watcher_pid: pid}}

          {:error, reason} ->
            Logger.warning(
              "[Perception.FileInbox] Could not start file_system watcher for #{state.path}: #{inspect(reason)}. " <>
                "If on Linux, install inotify-tools (sudo pacman -S inotify-tools / apt install inotify-tools)."
            )

            {:noreply, state}

          # FileSystem returns :ignore when the platform backend (inotify on
          # Linux, fsevents on macOS) cannot bootstrap. Don't crash the
          # supervisor — log and stay alive with no watcher.
          other ->
            Logger.warning(
              "[Perception.FileInbox] file_system unavailable for #{state.path} " <>
                "(returned #{inspect(other)}). On Linux, install inotify-tools."
            )

            {:noreply, state}
        end

      {:error, reason} ->
        Logger.warning(
          "[Perception.FileInbox] Could not prepare directory #{state.path}: #{inspect(reason)}"
        )

        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:file_event, watcher_pid, {path, events}}, %{watcher_pid: watcher_pid} = state) do
    if interesting_event?(events) and matches_extension?(path, state.extensions) do
      handle_file(path, state)
    end

    {:noreply, state}
  end

  def handle_info({:file_event, _pid, :stop}, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp ensure_dir(path) do
    case File.mkdir_p(path) do
      :ok -> :ok
      err -> err
    end
  end

  defp interesting_event?(events) do
    # We treat both new files and modifications as observations. Renames are
    # delivered as :renamed; we ignore deletions.
    Enum.any?(events, &(&1 in [:created, :modified, :renamed, :moved_to]))
  end

  defp matches_extension?(path, extensions) do
    ext = path |> Path.extname() |> String.trim_leading(".") |> String.downcase()
    ext in extensions
  end

  defp handle_file(path, state) do
    with {:ok, %{size: size}} <- File.stat(path),
         true <- size > 0 and size <= state.max_bytes,
         {:ok, content} <- File.read(path),
         {:ok, agent} <- resolve_agent(state.agent_id) do
      obs =
        RawObservation.new("file_inbox:#{Path.basename(path)}", content,
          title: Path.basename(path),
          external_id: external_id_for(path, content),
          trust_weight: state.trust_weight,
          metadata: %{"path" => path, "size" => size}
        )

      _ = Perception.ingest(agent, obs)
    else
      {:ok, %{size: size}} ->
        Logger.debug(
          "[Perception.FileInbox] Skipping #{path}: size #{size} outside [1, #{state.max_bytes}]"
        )

      false ->
        :skip

      {:error, reason} ->
        Logger.debug("[Perception.FileInbox] Skipping #{path}: #{inspect(reason)}")
    end
  rescue
    e ->
      Logger.debug("[Perception.FileInbox] Crash handling #{path}: #{Exception.message(e)}")
      :skip
  end

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

  defp external_id_for(path, content) do
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower) |> binary_part(0, 16)
    "#{Path.basename(path)}:#{hash}"
  end
end
