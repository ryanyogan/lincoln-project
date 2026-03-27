defmodule Lincoln.SelfAwareness.Introspection do
  @moduledoc """
  Runtime introspection capabilities for Lincoln's self-awareness.

  This module provides access to information about loaded BEAM modules,
  their functions, documentation, and more. Unlike the embedded source
  code, this reflects the actual running code.

  ## Examples

      # List all Lincoln modules
      Introspection.modules()

      # Get functions in a module
      Introspection.functions(Lincoln.Cognition.ThoughtLoop)

      # Get module documentation
      Introspection.module_doc(Lincoln.Cognition.ThoughtLoop)
  """

  alias Lincoln.SelfAwareness

  @doc """
  Returns all loaded modules that are part of Lincoln.

  ## Examples

      Introspection.modules()
      # => [Lincoln.Agents, Lincoln.Autonomy, Lincoln.Cognition, ...]
  """
  def modules do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&lincoln_module?/1)
    |> Enum.sort()
  end

  @doc """
  Returns all loaded modules matching a pattern.

  ## Examples

      Introspection.modules("Cognition")
      # => [Lincoln.Cognition, Lincoln.Cognition.ThoughtLoop, ...]
  """
  def modules(pattern) do
    modules()
    |> Enum.filter(fn mod ->
      mod |> to_string() |> String.contains?(pattern)
    end)
  end

  @doc """
  Returns the public functions defined in a module.

  ## Examples

      Introspection.functions(Lincoln.Cognition.ThoughtLoop)
      # => [{:run, 2}, {:run, 3}, ...]
  """
  def functions(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      module.__info__(:functions)
    else
      []
    end
  end

  @doc """
  Returns all functions (public and private) defined in a module.

  Note: Private functions are only available if the module was compiled
  with debug info.
  """
  def all_functions(module) when is_atom(module) do
    public = functions(module)
    # Private functions aren't directly accessible, but we can search source
    private = find_private_functions(module)
    Enum.uniq(public ++ private)
  end

  @doc """
  Returns the @moduledoc for a module.

  ## Examples

      Introspection.module_doc(Lincoln.Cognition.ThoughtLoop)
      # => "Lincoln's iterative reasoning process..."
  """
  def module_doc(module) when is_atom(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} -> doc
      {:docs_v1, _, _, _, :none, _, _} -> nil
      {:docs_v1, _, _, _, :hidden, _, _} -> nil
      _ -> nil
    end
  end

  @doc """
  Returns the @doc for a specific function.

  ## Examples

      Introspection.function_doc(Lincoln.Cognition.ThoughtLoop, :run, 2)
      # => "Runs the thought loop with given state and options..."
  """
  def function_doc(module, function, arity) when is_atom(module) and is_atom(function) do
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        docs
        |> Enum.find(fn
          {{:function, ^function, ^arity}, _, _, _, _} -> true
          _ -> false
        end)
        |> case do
          {_, _, _, %{"en" => doc}, _} -> doc
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Returns the source file path for a module (if available).

  ## Examples

      Introspection.source_location(Lincoln.Cognition.ThoughtLoop)
      # => "lib/lincoln/cognition/thought_loop.ex"
  """
  def source_location(module) when is_atom(module) do
    case module.module_info(:compile)[:source] do
      nil ->
        nil

      source when is_list(source) ->
        source
        |> to_string()
        |> extract_relative_path()

      source when is_binary(source) ->
        extract_relative_path(source)
    end
  rescue
    _ -> nil
  end

  @doc """
  Returns module attributes (compile-time metadata).

  ## Examples

      Introspection.attributes(Lincoln.Cognition.ThoughtLoop)
      # => [vsn: [...], behaviour: [...], ...]
  """
  def attributes(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      module.module_info(:attributes)
    else
      []
    end
  end

  @doc """
  Returns a summary of a module: functions, docs, source location.

  ## Examples

      Introspection.module_summary(Lincoln.Cognition.ThoughtLoop)
      # => %{
      #      name: Lincoln.Cognition.ThoughtLoop,
      #      source: "lib/lincoln/cognition/thought_loop.ex",
      #      doc: "Lincoln's iterative reasoning...",
      #      functions: [{:run, 2}, ...],
      #      function_count: 15
      #    }
  """
  def module_summary(module) when is_atom(module) do
    funcs = functions(module)

    %{
      name: module,
      source: source_location(module),
      doc: module_doc(module) |> truncate_doc(200),
      functions: Enum.take(funcs, 20),
      function_count: length(funcs)
    }
  end

  @doc """
  Returns summaries for all Lincoln modules.

  Useful for getting an overview of the entire codebase structure.
  """
  def all_module_summaries do
    modules()
    |> Enum.map(&module_summary/1)
  end

  @doc """
  Checks if a module is loaded and available.
  """
  def module_loaded?(module) when is_atom(module) do
    Code.ensure_loaded?(module)
  end

  @doc """
  Returns the behaviours implemented by a module.

  ## Examples

      Introspection.behaviours(Lincoln.Workers.AutonomousLearningWorker)
      # => [Oban.Worker]
  """
  def behaviours(module) when is_atom(module) do
    attributes(module)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end

  @doc """
  Returns callbacks defined by a behaviour module.
  """
  def callbacks(module) when is_atom(module) do
    if Code.ensure_loaded?(module) do
      case module.behaviour_info(:callbacks) do
        callbacks when is_list(callbacks) -> callbacks
        _ -> []
      end
    else
      []
    end
  rescue
    _ -> []
  end

  @doc """
  Returns a dependency graph of Lincoln modules (which modules use which).

  Note: This is based on source code analysis, not runtime information.
  """
  def module_dependencies do
    SelfAwareness.list_files("lib/lincoln")
    |> Enum.filter(&String.ends_with?(&1, ".ex"))
    |> Enum.map(fn path ->
      {:ok, content} = SelfAwareness.read(path)
      aliases = extract_aliases(content)
      {path, aliases}
    end)
    |> Enum.into(%{})
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp lincoln_module?(module) do
    module
    |> to_string()
    |> String.starts_with?("Elixir.Lincoln")
  end

  defp extract_relative_path(full_path) do
    case String.split(full_path, "/apps/lincoln/") do
      [_, relative] -> relative
      _ -> full_path |> Path.basename()
    end
  end

  defp truncate_doc(nil, _), do: nil

  defp truncate_doc(doc, max_length) do
    if String.length(doc) > max_length do
      String.slice(doc, 0, max_length) <> "..."
    else
      doc
    end
  end

  defp find_private_functions(module) do
    case source_location(module) do
      nil ->
        []

      source ->
        case SelfAwareness.read(source) do
          {:ok, content} ->
            Regex.scan(~r/defp\s+(\w+)/, content)
            |> Enum.map(fn [_, name] -> {String.to_atom(name), :unknown} end)

          _ ->
            []
        end
    end
  end

  defp extract_aliases(content) do
    Regex.scan(~r/alias\s+([A-Z][A-Za-z0-9_.]+)/, content)
    |> Enum.map(fn [_, alias_name] -> alias_name end)
    |> Enum.filter(&String.starts_with?(&1, "Lincoln"))
    |> Enum.uniq()
  end
end
