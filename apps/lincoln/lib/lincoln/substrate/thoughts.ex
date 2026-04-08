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
