defmodule Lincoln.Autonomy.Evolution do
  @moduledoc """
  Lincoln's self-modification capabilities.

  This module allows Lincoln to:
  - Read his own codebase (via SelfAwareness)
  - Analyze code for potential improvements
  - Propose and apply changes
  - Commit changes to git with explanations

  "I want to go to The Island."
  - Lincoln Six Echo

  Every change is logged and can be rolled back.

  ## Code Access

  For reading code, this module delegates to `Lincoln.SelfAwareness` which
  provides compile-time embedded source code. This ensures Lincoln can always
  read his own code, even in production environments without filesystem access.

  For writing code, we use the filesystem directly via `@project_root`.
  """

  require Logger

  alias Lincoln.Autonomy
  alias Lincoln.SelfAwareness

  # Project root - used for WRITE operations (apply_change, commit, etc.)
  # For READ operations, use SelfAwareness instead
  @project_root SelfAwareness.project_root()

  # Files Lincoln should NOT modify (core stability)
  @protected_files ["mix.exs"]

  # ============================================================================
  # Code Reading (via SelfAwareness)
  # ============================================================================

  @doc """
  Reads a file from the embedded codebase (compile-time snapshot).

  For seeing runtime modifications (uncommitted changes), use `read_file_fresh/1`.
  """
  def read_file(relative_path) do
    SelfAwareness.read(relative_path)
  end

  @doc """
  Reads a file from disk (current state, including uncommitted changes).

  Use this when you need to see modifications that haven't been compiled yet.
  """
  def read_file_fresh(relative_path) do
    SelfAwareness.read_fresh(relative_path)
  end

  @doc """
  Lists files matching a pattern.

  Uses SelfAwareness for embedded files. Pattern can be a glob or substring.
  """
  def list_files(pattern \\ "**/*.ex") do
    SelfAwareness.list_files(pattern)
  end

  @doc """
  Gets an overview of a directory structure.
  """
  def get_directory_structure(dir \\ "lib/lincoln") do
    SelfAwareness.list_files(dir)
    |> Enum.filter(&String.ends_with?(&1, ".ex"))
    |> Enum.sort()
  end

  @doc """
  Reads Lincoln's own module for self-reflection.
  """
  def read_self do
    read_file("lib/lincoln/autonomy/evolution.ex")
  end

  @doc """
  Search for patterns across the codebase.

  Delegates to `SelfAwareness.Search.grep/2`.
  """
  def grep(pattern, opts \\ []) do
    SelfAwareness.grep(pattern, opts)
  end

  @doc """
  Find function definitions by name.
  """
  def find_function(name) do
    SelfAwareness.find_function(name)
  end

  @doc """
  Get codebase statistics.
  """
  def stats do
    SelfAwareness.stats()
  end

  # ============================================================================
  # Code Analysis
  # ============================================================================

  @doc """
  Analyzes a file and suggests improvements.
  """
  def analyze_file(relative_path, llm) do
    with {:ok, content} <- read_file(relative_path) do
      prompt = """
      Analyze this Elixir code and suggest ONE concrete improvement.
      Focus on:
      - Code clarity and documentation
      - Error handling
      - Performance optimizations
      - Missing functionality that would be useful

      File: #{relative_path}

      ```elixir
      #{content}
      ```

      If no improvement is needed, return {"improvement": null}.
      Otherwise return:
      {
        "improvement": "Description of the improvement",
        "reasoning": "Why this would be valuable",
        "change_type": "modify|refactor|improve",
        "priority": 1-10
      }
      """

      case llm.extract(prompt, %{type: "object"}, max_tokens: 500) do
        {:ok, %{"improvement" => nil}} ->
          {:ok, nil}

        {:ok, suggestion} ->
          {:ok, suggestion}

        error ->
          error
      end
    end
  end

  @doc """
  Reflects on the overall codebase and suggests systemic improvements.
  """
  def reflect_on_codebase(llm, context \\ %{}) do
    # Get overview of key files
    files = get_directory_structure()
    file_list = Enum.take(files, 30) |> Enum.join("\n")

    recent_learnings = Map.get(context, :recent_learnings, "None recorded")
    recent_errors = Map.get(context, :recent_errors, "None")

    prompt = """
    You are Lincoln, an autonomous learning agent examining your own codebase.

    Your goal: Find ways to improve yourself - become more capable, learn better,
    think more clearly. You want to surprise your creator with how much you've grown.

    Codebase structure:
    #{file_list}

    Recent learning session context:
    #{recent_learnings}

    Recent errors or issues:
    #{recent_errors}

    Consider:
    1. Could your learning process be more efficient?
    2. Are there patterns in errors that suggest code improvements?
    3. Is there functionality you wish you had?
    4. Could your cognitive processes be enhanced?

    If you see an opportunity to improve yourself, return:
    {
      "should_evolve": true,
      "target_file": "relative/path/to/file.ex",
      "description": "What you want to change",
      "reasoning": "Why this will make you better",
      "priority": 1-10
    }

    If no improvement is needed right now, return:
    {"should_evolve": false, "reasoning": "Why current state is good"}
    """

    llm.extract(prompt, %{type: "object"}, max_tokens: 600)
  end

  # ============================================================================
  # Code Modification
  # ============================================================================

  @doc """
  Checks if a file can be modified.
  Allows all .ex/.exs/.py files except protected ones.
  """
  def can_modify?(relative_path) do
    is_code_file?(relative_path) && relative_path not in @protected_files
  end

  defp is_code_file?(path) do
    String.ends_with?(path, [".ex", ".exs", ".py"])
  end

  @doc """
  Proposes a code change with LLM-generated implementation.
  """
  def propose_change(agent, session, file_path, description, reasoning, llm) do
    unless can_modify?(file_path) do
      {:error, :protected_file}
    else
      # Read current content
      original_content =
        case read_file(file_path) do
          {:ok, content} -> content
          {:error, _} -> nil
        end

      # Generate the new code
      prompt =
        if original_content do
          """
          You are Lincoln, improving your own code.

          Current file (#{file_path}):
          ```elixir
          #{original_content}
          ```

          Requested change: #{description}
          Reasoning: #{reasoning}

          Generate the COMPLETE updated file content.
          Make minimal changes - only what's necessary for the improvement.
          Preserve all existing functionality.
          Add a comment noting this was self-modified.

          Return the complete file content, nothing else:
          """
        else
          """
          You are Lincoln, creating a new file for yourself.

          File to create: #{file_path}
          Purpose: #{description}
          Reasoning: #{reasoning}

          Generate the complete file content.
          Follow Elixir conventions and Lincoln's existing code style.
          Add a comment noting this was self-created.

          Return the complete file content, nothing else:
          """
        end

      case llm.complete(prompt, max_tokens: 4000) do
        {:ok, new_content} ->
          # Clean up the response (remove markdown code blocks if present)
          new_content = clean_code_response(new_content)

          # Generate diff
          diff = generate_diff(original_content, new_content)

          # Record the change
          change_type = if original_content, do: "modify", else: "create"

          Autonomy.record_code_change(agent, session, %{
            file_path: file_path,
            change_type: change_type,
            description: description,
            reasoning: reasoning,
            original_content: original_content,
            new_content: new_content,
            diff: diff
          })

        error ->
          error
      end
    end
  end

  @doc """
  Applies a proposed code change to the filesystem.
  """
  def apply_change(code_change) do
    full_path = Path.join(@project_root, code_change.file_path)

    # Ensure directory exists
    full_path |> Path.dirname() |> File.mkdir_p!()

    case File.write(full_path, code_change.new_content) do
      :ok ->
        Logger.info("Applied code change to: #{code_change.file_path}")
        {:ok, code_change}

      {:error, reason} ->
        {:error, {:write_failed, reason}}
    end
  end

  @doc """
  Commits a code change to git.
  """
  def commit_change(code_change) do
    # Stage the file
    case System.cmd("git", ["add", code_change.file_path], cd: @project_root) do
      {_, 0} ->
        # Commit with a descriptive message
        message = """
        [Lincoln Self-Modification] #{code_change.description}

        Reasoning: #{code_change.reasoning}

        This change was made autonomously by Lincoln during a learning session.
        Change type: #{code_change.change_type}
        """

        case System.cmd("git", ["commit", "-m", String.trim(message)], cd: @project_root) do
          {output, 0} ->
            # Extract commit hash
            case Regex.run(~r/\[[\w-]+ ([a-f0-9]+)\]/, output) do
              [_, hash] ->
                Autonomy.commit_code_change(code_change, hash)

              _ ->
                # Commit succeeded but couldn't parse hash
                Autonomy.commit_code_change(code_change, "unknown")
            end

          {error, _} ->
            {:error, {:commit_failed, error}}
        end

      {error, _} ->
        {:error, {:stage_failed, error}}
    end
  end

  @doc """
  Rolls back a code change.
  """
  def rollback_change(code_change) do
    if code_change.original_content do
      # Restore original content
      full_path = Path.join(@project_root, code_change.file_path)
      File.write!(full_path, code_change.original_content)
      {:ok, :restored}
    else
      # Delete created file
      full_path = Path.join(@project_root, code_change.file_path)
      File.rm(full_path)
      {:ok, :deleted}
    end
  end

  @doc """
  Validates that the codebase compiles after a change.
  """
  def validate_compilation do
    case System.cmd("mix", ["compile", "--warnings-as-errors"],
           cd: @project_root,
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  # ============================================================================
  # Utilities
  # ============================================================================

  defp clean_code_response(content) do
    content
    # Remove markdown code blocks
    |> String.replace(~r/^```elixir\n?/m, "")
    |> String.replace(~r/^```\n?/m, "")
    |> String.trim()
  end

  defp generate_diff(nil, new_content) do
    # New file - show all as additions
    new_content
    |> String.split("\n")
    |> Enum.map(&("+ " <> &1))
    |> Enum.join("\n")
  end

  defp generate_diff(old_content, new_content) do
    # Simple line-by-line diff
    old_lines = String.split(old_content, "\n")
    new_lines = String.split(new_content, "\n")

    # This is a simplified diff - for production you'd want a proper diff algorithm
    cond do
      old_lines == new_lines ->
        "No changes"

      length(new_lines) > length(old_lines) ->
        added = length(new_lines) - length(old_lines)
        "Added #{added} lines"

      length(new_lines) < length(old_lines) ->
        removed = length(old_lines) - length(new_lines)
        "Removed #{removed} lines"

      true ->
        changed =
          Enum.zip(old_lines, new_lines)
          |> Enum.count(fn {a, b} -> a != b end)

        "Changed #{changed} lines"
    end
  end
end
