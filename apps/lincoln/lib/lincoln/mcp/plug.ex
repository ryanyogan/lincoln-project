defmodule Lincoln.MCP.Plug do
  @moduledoc false

  @behaviour Plug

  alias Lincoln.MCP.Server

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%{request_path: "/mcp" <> _} = conn, _opts) do
    Server.call(conn, Server.init([]))
  end

  def call(conn, _opts), do: conn
end
