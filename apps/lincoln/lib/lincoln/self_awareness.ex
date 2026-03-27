defmodule Lincoln.SelfAwareness do
  @moduledoc """
  Lincoln's self-awareness of his own source code.

  This module provides Lincoln with always-available, fast access to his own codebase.
  All source files are embedded at compile time, ensuring:

  1. **Always works** - No disk I/O failures, no path issues
  2. **Fast** - Direct map lookup, no syscalls
  3. **Consistent** - Code matches what's actually running
  4. **Searchable** - grep/find across entire codebase instantly

  ## Usage

      # Read a file
      {:ok, content} = SelfAwareness.read("lib/lincoln/cognition/thought_loop.ex")

      # Search for patterns
      results = SelfAwareness.Search.grep("def process_message")

      # Introspect loaded modules
      modules = SelfAwareness.Introspection.modules()

  ## Embedded Files

  At compile time, we embed:
  - `lib/lincoln/**/*.ex` - Brain code
  - `lib/lincoln_web/**/*.ex` - Web code (LiveViews, components)
  - `lib/lincoln_web/**/*.html.heex` - Templates
  - `test/**/*.ex` - Test files
  - `config/*.exs` - Configuration
  - `mix.exs` - Project definition

  The embedded code is from compile time. Use `read_fresh/1` to read
  current disk content (for seeing uncommitted modifications).
  """

  require Logger

  # =============================================================================
  # Compile-Time Setup
  # =============================================================================

  # Project root - relative to this file's location
  # This file is at lib/lincoln/self_awareness.ex
  # So ../.. gets us to the app root (apps/lincoln/)
  @project_root Path.expand("../..", __DIR__)

  # Patterns for files to embed
  @source_patterns [
    "lib/lincoln/**/*.ex",
    "lib/lincoln_web/**/*.ex",
    "lib/lincoln_web/**/*.html.heex",
    "test/**/*.ex",
    "config/*.exs",
    "mix.exs",
    "mix.lock"
  ]

  # Gather all files matching our patterns
  @all_source_files @source_patterns
                    |> Enum.flat_map(fn pattern ->
                      Path.join(@project_root, pattern) |> Path.wildcard()
                    end)
                    |> Enum.uniq()
                    |> Enum.sort()

  # Mark all source files as external resources
  # This causes automatic recompilation when any source file changes
  for path <- @all_source_files do
    @external_resource path
  end

  # Embed all source at compile time
  @embedded_sources @all_source_files
                    |> Enum.map(fn full_path ->
                      relative = Path.relative_to(full_path, @project_root)

                      content =
                        case File.read(full_path) do
                          {:ok, content} -> content
                          {:error, _} -> ""
                        end

                      {relative, content}
                    end)
                    |> Map.new()

  # Pre-compute statistics
  @stats %{
    files: map_size(@embedded_sources),
    bytes: @embedded_sources |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum(),
    lines:
      @embedded_sources
      |> Map.values()
      |> Enum.map(fn content -> content |> String.split("\n") |> length() end)
      |> Enum.sum()
  }

  # Store project root for fresh reads
  @compile_time_root @project_root

  # =============================================================================
  # Public API - File Access
  # =============================================================================

  @doc """
  Reads a file from the embedded source code (compile-time snapshot).

  Returns `{:ok, content}` or `{:error, :not_found}`.

  ## Examples

      {:ok, content} = SelfAwareness.read("lib/lincoln/cognition/thought_loop.ex")
      {:error, :not_found} = SelfAwareness.read("nonexistent.ex")
  """
  def read(path) do
    normalized = normalize_path(path)

    case Map.fetch(@embedded_sources, normalized) do
      {:ok, content} -> {:ok, content}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Reads a file from the embedded source code, raises on missing.

  ## Examples

      content = SelfAwareness.read!("lib/lincoln/cognition/thought_loop.ex")
  """
  def read!(path) do
    case read(path) do
      {:ok, content} -> content
      {:error, :not_found} -> raise "File not found in embedded sources: #{path}"
    end
  end

  @doc """
  Reads a file from disk (not embedded). Use this to see runtime modifications
  that haven't been compiled yet.

  Returns `{:ok, content}` or `{:error, reason}`.

  ## Examples

      # See uncommitted changes
      {:ok, content} = SelfAwareness.read_fresh("lib/lincoln/cognition/thought_loop.ex")
  """
  def read_fresh(path) do
    normalized = normalize_path(path)
    full_path = Path.join(@compile_time_root, normalized)

    case File.read(full_path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists all embedded files.

  ## Examples

      files = SelfAwareness.list_files()
      # => ["config/config.exs", "lib/lincoln/agents.ex", ...]
  """
  def list_files do
    @embedded_sources |> Map.keys() |> Enum.sort()
  end

  @doc """
  Lists files matching a glob pattern or substring.

  ## Examples

      # Glob pattern
      SelfAwareness.list_files("lib/lincoln/cognition/*.ex")
      # => ["lib/lincoln/cognition/thought_loop.ex", ...]

      # Substring match
      SelfAwareness.list_files("cognition")
      # => ["lib/lincoln/cognition.ex", "lib/lincoln/cognition/thought_loop.ex", ...]
  """
  def list_files(pattern) do
    if String.contains?(pattern, "*") do
      # Glob pattern - match against all files
      regex = glob_to_regex(pattern)

      list_files()
      |> Enum.filter(&Regex.match?(regex, &1))
    else
      # Substring match
      list_files()
      |> Enum.filter(&String.contains?(&1, pattern))
    end
  end

  @doc """
  Returns all embedded sources as a map of `{path => content}`.
  """
  def all do
    @embedded_sources
  end

  @doc """
  Returns statistics about the embedded codebase.

  ## Examples

      SelfAwareness.stats()
      # => %{files: 74, bytes: 520000, lines: 17000}
  """
  def stats do
    @stats
  end

  @doc """
  Returns information about a specific file.

  ## Examples

      SelfAwareness.file_info("lib/lincoln/cognition/thought_loop.ex")
      # => %{lines: 500, bytes: 15000, exists: true}
  """
  def file_info(path) do
    case read(path) do
      {:ok, content} ->
        %{
          exists: true,
          bytes: byte_size(content),
          lines: content |> String.split("\n") |> length()
        }

      {:error, _} ->
        %{exists: false, bytes: 0, lines: 0}
    end
  end

  @doc """
  Returns the project root path (compile-time value).
  Useful for operations that need to write files.
  """
  def project_root do
    @compile_time_root
  end

  @doc """
  Checks if a file exists in the embedded sources.
  """
  def exists?(path) do
    normalized = normalize_path(path)
    Map.has_key?(@embedded_sources, normalized)
  end

  # =============================================================================
  # Delegations to submodules
  # =============================================================================

  defdelegate grep(pattern), to: Lincoln.SelfAwareness.Search
  defdelegate grep(pattern, opts), to: Lincoln.SelfAwareness.Search
  defdelegate find_function(name), to: Lincoln.SelfAwareness.Search
  defdelegate find_module(name), to: Lincoln.SelfAwareness.Search

  defdelegate modules(), to: Lincoln.SelfAwareness.Introspection
  defdelegate functions(module), to: Lincoln.SelfAwareness.Introspection
  defdelegate module_doc(module), to: Lincoln.SelfAwareness.Introspection

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp normalize_path(path) do
    path
    |> String.trim_leading("/")
    |> String.trim_leading("apps/lincoln/")
  end

  defp glob_to_regex(pattern) do
    pattern
    |> Regex.escape()
    |> String.replace("\\*\\*", ".*")
    |> String.replace("\\*", "[^/]*")
    |> then(&Regex.compile!("^#{&1}$"))
  end
end
