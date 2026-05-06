defmodule Lincoln.MCP.StdioSupervisor do
  @moduledoc """
  DynamicSupervisor for `Lincoln.MCP.StdioServer` children.

  Stdio MCP servers are started lazily on first lookup so unconfigured
  servers don't spawn subprocesses. `Lincoln.MCP.Client` calls
  `ensure_started/2` before dispatching a request to the named server.
  """

  use DynamicSupervisor

  alias Lincoln.MCP.StdioServer

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Look up or start a stdio server for the given name. `cfg` is the
  keyword list from `:lincoln, :mcp_servers` for this server, expected
  to contain `:command` and optionally `:args`.
  """
  def ensure_started(name, cfg) when is_atom(name) and is_list(cfg) do
    case Registry.lookup(Lincoln.MCP.StdioRegistry, name) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        opts = [
          name: name,
          command: Keyword.fetch!(cfg, :command),
          args: Keyword.get(cfg, :args, []),
          env: Keyword.get(cfg, :env, [])
        ]

        spec = %{id: {StdioServer, name}, start: {StdioServer, :start_link, [opts]}, restart: :transient}

        case DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} = err -> err
        end
    end
  end
end
