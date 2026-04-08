defmodule Lincoln.Substrate.Thoughts do
  @moduledoc """
  Public API for inspecting running Thought processes.

  Thoughts are short-lived — they spawn, execute, and terminate.
  Use this module to observe what Lincoln is currently thinking about.
  """

  alias Lincoln.Substrate.{Thought, ThoughtSupervisor}

  @doc """
  List all currently running thoughts for an agent.
  Returns a list of thought state structs.
  """
  def list(agent_id) when is_binary(agent_id) do
    agent_id
    |> ThoughtSupervisor.list_children()
    |> Enum.flat_map(fn {_id, pid, _type, _modules} ->
      case pid do
        :restarting ->
          []

        pid when is_pid(pid) ->
          try do
            [Thought.get_state(pid)]
          catch
            :exit, _ -> []
          end
      end
    end)
  end

  @doc """
  Count of currently running thoughts for an agent.
  """
  def count(agent_id) when is_binary(agent_id) do
    agent_id
    |> ThoughtSupervisor.list_children()
    |> Enum.count(fn {_id, pid, _type, _modules} ->
      is_pid(pid)
    end)
  end

  @doc """
  Returns running thoughts organized as a tree — parents with children nested.
  Returns [%{thought: parent_state, children: [child_states]}].
  Orphaned children (parent already completed) appear as roots with empty children.
  """
  def list_tree(agent_id) when is_binary(agent_id) do
    all_thoughts = list(agent_id)

    {roots, children} =
      Enum.split_with(all_thoughts, fn t -> is_nil(t.parent_id) end)

    children_by_parent = Enum.group_by(children, & &1.parent_id)

    root_ids = MapSet.new(roots, & &1.id)

    tree =
      Enum.map(roots, fn root ->
        %{thought: root, children: Map.get(children_by_parent, root.id, [])}
      end)

    orphans =
      children
      |> Enum.reject(fn c -> MapSet.member?(root_ids, c.parent_id) end)
      |> Enum.map(fn orphan -> %{thought: orphan, children: []} end)

    tree ++ orphans
  end

  @doc """
  Find a specific thought by its ID.
  Returns `{:ok, state}` if found, `{:error, :not_found}` if not.
  """
  def get(agent_id, thought_id) when is_binary(agent_id) and is_binary(thought_id) do
    result =
      agent_id
      |> list()
      |> Enum.find(fn state -> state.id == thought_id end)

    case result do
      nil -> {:error, :not_found}
      state -> {:ok, state}
    end
  end
end
