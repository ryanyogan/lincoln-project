defmodule Lincoln.MCP.StdioServer do
  @moduledoc """
  Long-lived GenServer wrapping a stdio MCP server subprocess.

  The MCP stdio transport is newline-delimited JSON-RPC over the child
  process's stdin/stdout. The protocol requires an `initialize` request
  followed by a `notifications/initialized` notification before any
  `tools/call` or `tools/list` is allowed (per the MCP lifecycle spec),
  so the client side must hold a persistent connection — a stateless
  port-per-call would re-handshake on every request.

  ## Why a per-server GenServer (not stateless calls)

  - The MCP handshake is mandatory and ordered.
  - The connection is meant to persist for the life of the client.
  - Responses are correlated to requests by `id`, which means we need a
    process that owns the read side and dispatches to the right caller.

  ## Framing

  We use `Port.open(..., [:binary, {:line, 1_048_576}, ...])`. With the
  `:line` option the BEAM emits `{port, {:data, {:eol, line}}}` per
  complete newline-terminated line and `{:noeol, chunk}` for partials
  larger than the max. This matches MCP stdio's "messages must be
  newline-delimited and cannot contain embedded newlines" rule exactly,
  so we don't have to scan a binary buffer for `\\n` ourselves.

  ## Spawning

  We use `:spawn_executable` rather than `:spawn` because `:spawn`
  tokenizes the command string by space and breaks on paths/args
  containing spaces. `:spawn_executable` + `:args` passes args directly
  to `execv`, which is the safe form documented in the `Port` module.

  ## Orphan-process caveat

  Closing the BEAM does not necessarily kill the subprocess. We rely on
  the convention that well-behaved MCP servers (`mcp-server-fetch`
  included) exit when their stdin is closed, which the BEAM does
  automatically on `Port.close/1` or process death.
  """

  use GenServer

  require Logger

  @protocol_version "2025-06-18"
  @client_info %{name: "lincoln", version: "0.1.0"}
  @initialize_timeout_ms 10_000
  @default_call_timeout_ms 30_000
  @max_line_bytes 1_048_576

  defstruct [
    :name,
    :port,
    :exe,
    :args,
    :env,
    buffer: "",
    pending: %{},
    pending_pre_init: :queue.new(),
    next_id: 1,
    initialized?: false,
    init_from: nil
  ]

  ## Public API

  @doc """
  Start a stdio MCP server linked to the caller. Caller is typically the
  `StdioSupervisor`. Registers the GenServer under
  `Lincoln.MCP.StdioRegistry` keyed by `name`.
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: via(name))
  end

  @doc """
  Make an MCP JSON-RPC request and wait for the response. Used for
  `tools/list`, `tools/call`, etc. Notifications are not sent through
  this path.
  """
  def rpc(name, method, params, timeout \\ @default_call_timeout_ms)
      when is_atom(name) and is_binary(method) do
    GenServer.call(via(name), {:rpc, method, params}, timeout)
  catch
    :exit, {:noproc, _} -> {:error, :stdio_server_not_running}
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  defp via(name), do: {:via, Registry, {Lincoln.MCP.StdioRegistry, name}}

  ## GenServer callbacks

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    env = Keyword.get(opts, :env, [])

    case System.find_executable(command) do
      nil ->
        {:stop, {:executable_not_found, command}}

      exe ->
        Process.flag(:trap_exit, true)

        port_opts =
          [:binary, :exit_status, {:line, @max_line_bytes}, args: args]
          |> maybe_with_env(env)

        port = Port.open({:spawn_executable, exe}, port_opts)
        state = %__MODULE__{name: name, port: port, exe: exe, args: args, env: env}

        case send_initialize(state) do
          {:ok, state} -> {:ok, state}
          {:error, reason} -> {:stop, reason}
        end
    end
  end

  # Erlang ports accept env as `[{charlist, charlist}]`. We accept either
  # the keyword/list-of-tuples form (with binaries) or already-charlisted
  # entries and normalize. An empty list means "inherit parent env" — we
  # only attach the option when at least one entry exists.
  defp maybe_with_env(port_opts, []), do: port_opts

  defp maybe_with_env(port_opts, env) do
    normalized =
      Enum.map(env, fn
        {k, v} when is_binary(k) and is_binary(v) ->
          {String.to_charlist(k), String.to_charlist(v)}

        {k, v} when is_list(k) and is_list(v) ->
          {k, v}
      end)

    [{:env, normalized} | port_opts]
  end

  @impl true
  def handle_call({:rpc, method, params}, from, %{initialized?: true} = state) do
    {id, state} = next_id(state)
    state = %{state | pending: Map.put(state.pending, id, from)}
    write_request(state.port, id, method, params)
    {:noreply, state}
  end

  @impl true
  def handle_call({:rpc, _, _} = msg, from, %{initialized?: false} = state) do
    queue = :queue.in({msg, from}, state.pending_pre_init)
    {:noreply, %{state | pending_pre_init: queue}}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port, buffer: buf} = state) do
    full_line = buf <> line
    state = %{state | buffer: ""}
    handle_line(full_line, state)
  end

  @impl true
  def handle_info({port, {:data, {:noeol, chunk}}}, %{port: port, buffer: buf} = state) do
    {:noreply, %{state | buffer: buf <> chunk}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("[MCP.StdioServer/#{state.name}] subprocess exited with status #{status}")

    fail_all_pending(state, {:stdio_server_exited, status})
    {:stop, {:shutdown, {:exit_status, status}}, %{state | port: nil}}
  end

  @impl true
  def handle_info({port, :closed}, %{port: port} = state) do
    fail_all_pending(state, :stdio_server_closed)
    {:stop, {:shutdown, :closed}, %{state | port: nil}}
  end

  @impl true
  def handle_info(:initialize_timeout, %{initialized?: false, init_from: nil} = state) do
    Logger.error("[MCP.StdioServer/#{state.name}] initialize handshake timed out")
    {:stop, {:shutdown, :initialize_timeout}, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{port: port}) when is_port(port) do
    try do
      Port.close(port)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  ## Internals

  defp send_initialize(state) do
    {id, state} = next_id(state)

    write_request(state.port, id, "initialize", %{
      protocolVersion: @protocol_version,
      capabilities: %{},
      clientInfo: @client_info
    })

    receive_initialize(id, state)
  end

  defp receive_initialize(expected_id, state) do
    receive do
      {port, {:data, {:eol, line}}} when port == state.port ->
        case Jason.decode(line) do
          {:ok, %{"id" => ^expected_id, "result" => _result}} ->
            send_initialized_notification(state.port)
            state = %{state | initialized?: true}
            state = drain_pre_init(state)
            {:ok, state}

          {:ok, %{"id" => ^expected_id, "error" => err}} ->
            {:error, {:initialize_failed, err}}

          {:ok, _other} ->
            receive_initialize(expected_id, state)

          {:error, _} ->
            receive_initialize(expected_id, state)
        end

      {port, {:data, {:noeol, _}}} when port == state.port ->
        receive_initialize(expected_id, state)

      {port, {:exit_status, status}} when port == state.port ->
        {:error, {:exited_during_init, status}}
    after
      @initialize_timeout_ms ->
        {:error, :initialize_timeout}
    end
  end

  defp send_initialized_notification(port) do
    line = Jason.encode!(%{jsonrpc: "2.0", method: "notifications/initialized"})
    Port.command(port, line <> "\n")
  end

  defp drain_pre_init(%{pending_pre_init: queue} = state) do
    case :queue.out(queue) do
      {:empty, _} ->
        state

      {{:value, {{:rpc, method, params}, from}}, rest} ->
        {id, state} = next_id(%{state | pending_pre_init: rest})
        state = %{state | pending: Map.put(state.pending, id, from)}
        write_request(state.port, id, method, params)
        drain_pre_init(state)
    end
  end

  defp handle_line(line, state) do
    case Jason.decode(line) do
      {:ok, %{"id" => id} = msg} ->
        dispatch_response(id, msg, state)

      {:ok, %{"method" => method}} ->
        Logger.debug("[MCP.StdioServer/#{state.name}] received notification #{method}, ignored")

        {:noreply, state}

      {:error, reason} ->
        Logger.debug("[MCP.StdioServer/#{state.name}] non-JSON line dropped: #{inspect(reason)}")

        {:noreply, state}
    end
  end

  defp dispatch_response(id, msg, state) do
    case Map.pop(state.pending, id) do
      {nil, _} ->
        Logger.debug("[MCP.StdioServer/#{state.name}] response for unknown id #{inspect(id)}")
        {:noreply, state}

      {from, rest} ->
        reply =
          case msg do
            %{"result" => result} -> {:ok, result}
            %{"error" => err} -> {:error, {:rpc_error, err}}
            _ -> {:error, {:unexpected_body, msg}}
          end

        GenServer.reply(from, reply)
        {:noreply, %{state | pending: rest}}
    end
  end

  defp write_request(port, id, method, params) do
    body = %{jsonrpc: "2.0", id: id, method: method, params: params}
    line = Jason.encode!(body)
    Port.command(port, line <> "\n")
  end

  defp next_id(state), do: {state.next_id, %{state | next_id: state.next_id + 1}}

  defp fail_all_pending(%{pending: pending}, reason) do
    for {_id, from} <- pending do
      GenServer.reply(from, {:error, reason})
    end
  end
end
