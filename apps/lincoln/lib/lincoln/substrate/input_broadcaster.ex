defmodule Lincoln.Substrate.InputBroadcaster do
  @moduledoc """
  Broadcasts events to multiple agent Substrate processes simultaneously.
  Used for the divergence demo: same input -> different outputs from different params.
  """

  alias Lincoln.Substrate

  @doc "Broadcast event to ALL currently running agents."
  def broadcast_to_all(event) do
    Substrate.list_running_agents()
    |> Enum.each(fn agent_id ->
      Substrate.send_event(agent_id, event)
    end)
  end

  @doc "Broadcast event to a specific group of agents."
  def broadcast_to_group(agent_ids, event) when is_list(agent_ids) do
    Enum.each(agent_ids, fn agent_id ->
      case Substrate.send_event(agent_id, event) do
        :ok -> :ok
        {:error, :not_running} -> :ok
      end
    end)
  end
end
