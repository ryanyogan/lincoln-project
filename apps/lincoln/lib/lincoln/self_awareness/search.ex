defmodule Lincoln.SelfAwareness.Search do
  @moduledoc """
  Search capabilities for Lincoln's self-awareness.

  Provides grep-like pattern matching and semantic search across
  Lincoln's embedded source code.

  ## Examples

      # Find all usages of a function
      Search.grep("process_message")

      # Find function definitions
      Search.find_function("process_message")

      # Find module definitions
      Search.find_module("ThoughtLoop")

      # Search with path filter
      Search.grep("Logger", path: "cognition")
  """

  alias Lincoln.SelfAwareness

  @doc """
  Searches for a pattern across all embedded files.

  Returns a list of `{path, line_number, line_content}` tuples.

  ## Options

  - `:path` - Filter to files containing this substring in their path
  - `:limit` - Maximum number of results (default: 100)
  - `:case_sensitive` - Whether search is case-sensitive (default: true)

  ## Examples

      # Basic search
      Search.grep("def handle_info")
      # => [{"lib/lincoln_web/live/chat_live.ex", 165, "  def handle_info({:process_message, ..."}]

      # With path filter
      Search.grep("Logger.info", path: "cognition")

      # Case insensitive
      Search.grep("todo", case_sensitive: false)
  """
  def grep(pattern, opts \\ []) do
    path_filter = Keyword.get(opts, :path)
    limit = Keyword.get(opts, :limit, 100)
    case_sensitive = Keyword.get(opts, :case_sensitive, true)

    regex_opts = if case_sensitive, do: [], else: [:caseless]

    regex =
      case Regex.compile(pattern, regex_opts) do
        {:ok, regex} -> regex
        {:error, _} -> Regex.compile!(Regex.escape(pattern), regex_opts)
      end

    SelfAwareness.all()
    |> filter_by_path(path_filter)
    |> Enum.flat_map(fn {path, content} ->
      search_file(path, content, regex)
    end)
    |> Enum.take(limit)
  end

  @doc """
  Finds function definitions matching the given name.

  Searches for `def name(` and `defp name(` patterns.

  ## Examples

      Search.find_function("process_message")
      # => [{"lib/lincoln/cognition/conversation_handler.ex", 100, "  def process_message(agent_id, ..."}]
  """
  def find_function(name) do
    grep("def(p)?\\s+#{Regex.escape(name)}\\s*\\(", limit: 50)
  end

  @doc """
  Finds module definitions matching the given name.

  Searches for `defmodule ...Name` patterns.

  ## Examples

      Search.find_module("ThoughtLoop")
      # => [{"lib/lincoln/cognition/thought_loop.ex", 1, "defmodule Lincoln.Cognition.ThoughtLoop do"}]
  """
  def find_module(name) do
    grep("defmodule\\s+[A-Za-z0-9_.]*#{Regex.escape(name)}", limit: 50)
  end

  @doc """
  Finds all references to a term (function calls, variable uses, etc.).

  ## Examples

      Search.find_references("ThoughtLoop")
      # => [{"lib/lincoln/cognition.ex", 5, "  alias Lincoln.Cognition.ThoughtLoop"}, ...]
  """
  def find_references(term) do
    grep("\\b#{Regex.escape(term)}\\b", limit: 200)
  end

  @doc """
  Finds all @moduledoc and @doc annotations.

  Useful for understanding what documentation exists.
  """
  def find_docs(opts \\ []) do
    path_filter = Keyword.get(opts, :path)

    grep("@(moduledoc|doc)\\s+\"\"\"", path: path_filter, limit: 500)
  end

  @doc """
  Finds TODO, FIXME, and similar comments.
  """
  def find_todos do
    grep("(TODO|FIXME|HACK|XXX|BUG):", case_sensitive: false, limit: 200)
  end

  @doc """
  Searches for struct definitions.

  ## Examples

      Search.find_structs()
      # => [{"lib/lincoln/events/event.ex", 22, "  defstruct [:id, :type, ...]"}]
  """
  def find_structs do
    grep("defstruct\\s+\\[", limit: 100)
  end

  @doc """
  Searches for schema definitions (Ecto schemas).
  """
  def find_schemas do
    grep("schema\\s+\"[^\"]+\"\\s+do", limit: 100)
  end

  @doc """
  Returns a summary of where a term is used across the codebase.

  Groups results by file for easier reading.

  ## Examples

      Search.usage_summary("ThoughtLoop")
      # => %{
      #      "lib/lincoln/cognition.ex" => [5, 10, 45],
      #      "lib/lincoln/cognition/conversation_handler.ex" => [30]
      #    }
  """
  def usage_summary(term) do
    find_references(term)
    |> Enum.group_by(
      fn {path, _line_no, _content} -> path end,
      fn {_path, line_no, _content} -> line_no end
    )
  end

  @doc """
  Counts occurrences of a pattern, grouped by file.

  ## Examples

      Search.count_occurrences("Logger.info")
      # => %{"lib/lincoln/cognition/thought_loop.ex" => 15, ...}
  """
  def count_occurrences(pattern) do
    grep(pattern, limit: 10000)
    |> Enum.group_by(fn {path, _line_no, _content} -> path end)
    |> Enum.map(fn {path, matches} -> {path, length(matches)} end)
    |> Enum.into(%{})
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp filter_by_path(sources, nil), do: sources

  defp filter_by_path(sources, path_filter) do
    Enum.filter(sources, fn {path, _content} ->
      String.contains?(path, path_filter)
    end)
  end

  defp search_file(path, content, regex) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> Regex.match?(regex, line) end)
    |> Enum.map(fn {line, line_no} ->
      {path, line_no, String.trim(line)}
    end)
  end
end
