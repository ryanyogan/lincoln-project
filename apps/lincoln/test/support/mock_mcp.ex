defmodule MockMCP do
  @moduledoc """
  Lightweight `Lincoln.MCP.Client`-compatible test double, returned via
  `expect_success/1`, `expect_failure/1`, etc. Each helper builds a module
  that implements `call_tool/4` so tests can pass it as `mcp_client:` to
  `Lincoln.Actions.execute/2` without standing up a real Mox mock.

  The MCP client surface is `call_tool(server, tool, arguments, opts)`.
  """

  def expect_success(result) do
    fixed_module(:success, result)
  end

  def expect_failure(reason) do
    fixed_module(:failure, reason)
  end

  def expect_unused do
    fixed_module(:unused, nil)
  end

  defp fixed_module(:success, result) do
    parent = self()

    {:module, mod, _, _} =
      Module.create(
        Module.concat(__MODULE__, "Stub_#{:erlang.unique_integer([:positive])}"),
        quote do
          def call_tool(_server, tool, args, _opts \\ []) do
            send(unquote(parent), {:mock_mcp, :called, tool, args})
            {:ok, unquote(Macro.escape(result))}
          end
        end,
        Macro.Env.location(__ENV__)
      )

    mod
  end

  defp fixed_module(:failure, reason) do
    parent = self()

    {:module, mod, _, _} =
      Module.create(
        Module.concat(__MODULE__, "Stub_#{:erlang.unique_integer([:positive])}"),
        quote do
          def call_tool(_server, tool, args, _opts \\ []) do
            send(unquote(parent), {:mock_mcp, :called, tool, args})
            {:error, unquote(Macro.escape(reason))}
          end
        end,
        Macro.Env.location(__ENV__)
      )

    mod
  end

  defp fixed_module(:unused, _) do
    {:module, mod, _, _} =
      Module.create(
        Module.concat(__MODULE__, "Stub_#{:erlang.unique_integer([:positive])}"),
        quote do
          def call_tool(_server, _tool, _args, _opts \\ []) do
            raise "MCP should not be called"
          end
        end,
        Macro.Env.location(__ENV__)
      )

    mod
  end
end
