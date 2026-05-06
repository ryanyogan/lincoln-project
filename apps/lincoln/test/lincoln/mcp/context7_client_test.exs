defmodule Lincoln.MCP.Context7ClientTest do
  use ExUnit.Case, async: true

  alias Lincoln.MCP.Context7Client

  defmodule HappyClient do
    @moduledoc false
    def call_tool(_server, "resolve-library-id", _args, _opts) do
      {:ok,
       %{
         "content" => [
           %{
             "type" => "text",
             "text" =>
               "- Title: Phoenix LiveView\n- Context7-compatible library ID: /phoenixframework/phoenix_live_view\n  Snippets: 1234"
           }
         ]
       }}
    end

    def call_tool(_server, "query-docs", args, _opts) do
      {:ok,
       %{
         "content" => [
           %{"type" => "text", "text" => "## #{args.libraryId}\n\nUse stream/3 to..."}
         ]
       }}
    end
  end

  defmodule ResolveFailsClient do
    @moduledoc false
    def call_tool(_server, "resolve-library-id", _args, _opts), do: {:error, :timeout}
    def call_tool(_server, "query-docs", _args, _opts), do: {:error, :should_not_be_called}
  end

  defmodule NoMatchClient do
    @moduledoc false
    def call_tool(_server, "resolve-library-id", _args, _opts) do
      {:ok, %{"content" => [%{"type" => "text", "text" => "no matches found"}]}}
    end

    def call_tool(_server, "query-docs", _args, _opts), do: {:error, :should_not_be_called}
  end

  defmodule UnconfiguredClient do
    @moduledoc false
    def call_tool(_server, _tool, _args, _opts), do: {:error, :server_not_configured}
  end

  describe "lookup_docs/3" do
    test "happy path: resolves id then fetches docs and returns text" do
      assert {:ok, docs} =
               Context7Client.lookup_docs("phoenix_live_view", "streams", client: HappyClient)

      assert docs =~ "/phoenixframework/phoenix_live_view"
      assert docs =~ "stream/3"
    end

    test "threads resolved id into the docs call" do
      assert {:ok, docs} = Context7Client.lookup_docs("phoenix_live_view", "x", client: HappyClient)
      assert docs =~ "/phoenixframework/phoenix_live_view"
    end

    test "returns empty string when resolve fails" do
      assert {:ok, ""} =
               Context7Client.lookup_docs("phoenix", "streams", client: ResolveFailsClient)
    end

    test "returns empty string when no library matches" do
      assert {:ok, ""} = Context7Client.lookup_docs("nope", "x", client: NoMatchClient)
    end

    test "returns empty string when server is not configured" do
      assert {:ok, ""} = Context7Client.lookup_docs("phoenix", "x", client: UnconfiguredClient)
    end
  end
end
