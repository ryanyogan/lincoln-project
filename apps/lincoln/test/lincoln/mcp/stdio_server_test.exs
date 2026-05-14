defmodule Lincoln.MCP.StdioServerTest do
  use ExUnit.Case, async: false

  alias Lincoln.MCP.StdioServer

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Tiny dummy MCP-stdio server in pure Bash. Reads newline-delimited
    # JSON-RPC requests and responds appropriately:
    # - "initialize" → success result with serverInfo
    # - "echo" → echoes the params back as result
    # - everything else → JSON-RPC error -32601 (method not found)
    # We use jq for JSON shaping so the script stays minimal. If jq isn't
    # available we skip the test rather than reimplementing JSON in shell.
    script_path = Path.join(tmp_dir, "fake_mcp_server.sh")

    if System.find_executable("jq") == nil do
      {:skip, "jq not available — needed for the dummy stdio MCP server"}
    else
      File.write!(script_path, ~S"""
      #!/usr/bin/env bash
      set -e
      while IFS= read -r line; do
        method=$(echo "$line" | jq -r '.method // empty')
        id=$(echo "$line" | jq -c '.id // null')

        case "$method" in
          initialize)
            echo "{\"jsonrpc\":\"2.0\",\"id\":${id},\"result\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"fake\",\"version\":\"0\"}}}"
            ;;
          notifications/initialized)
            : # notification, no response
            ;;
          tools/call)
            params=$(echo "$line" | jq -c '.params.arguments')
            echo "{\"jsonrpc\":\"2.0\",\"id\":${id},\"result\":{\"echoed\":${params}}}"
            ;;
          tools/list)
            echo "{\"jsonrpc\":\"2.0\",\"id\":${id},\"result\":{\"tools\":[{\"name\":\"echo\"}]}}"
            ;;
          *)
            echo "{\"jsonrpc\":\"2.0\",\"id\":${id},\"error\":{\"code\":-32601,\"message\":\"method not found\"}}"
            ;;
        esac
      done
      """)

      File.chmod!(script_path, 0o755)

      # The application starts Lincoln.MCP.StdioRegistry, so we just reuse
      # it. Names are namespaced per-test (:test_echo, :test_list, ...) so
      # there's no collision.
      {:ok, script_path: script_path}
    end
  end

  describe "request/response correlation" do
    test "tools/call returns the response paired by id", %{script_path: script_path} do
      {:ok, _pid} =
        StdioServer.start_link(name: :test_echo, command: script_path, args: [])

      assert {:ok, %{"echoed" => %{"hello" => "world"}}} =
               StdioServer.rpc(:test_echo, "tools/call", %{
                 name: "echo",
                 arguments: %{hello: "world"}
               })
    end

    test "tools/list works after initialize handshake", %{script_path: script_path} do
      {:ok, _pid} =
        StdioServer.start_link(name: :test_list, command: script_path, args: [])

      assert {:ok, %{"tools" => [%{"name" => "echo"}]}} =
               StdioServer.rpc(:test_list, "tools/list", %{})
    end

    test "concurrent calls are correlated correctly", %{script_path: script_path} do
      {:ok, _pid} =
        StdioServer.start_link(name: :test_concurrent, command: script_path, args: [])

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            {i,
             StdioServer.rpc(:test_concurrent, "tools/call", %{
               name: "echo",
               arguments: %{n: i}
             })}
          end)
        end

      results = Task.await_many(tasks, 5_000)

      for {i, {:ok, %{"echoed" => %{"n" => n}}}} <- results do
        assert n == i
      end
    end
  end

  describe "failure modes" do
    test "executable not found stops the GenServer with a clear reason" do
      Process.flag(:trap_exit, true)

      result =
        StdioServer.start_link(name: :test_missing, command: "no_such_binary_xyz", args: [])

      assert {:error, {:executable_not_found, "no_such_binary_xyz"}} = result
    end
  end
end
