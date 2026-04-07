defmodule Lincoln.Substrate.Attention do
  @moduledoc """
  The Attention GenServer decides "what to think about next" using round-robin
  over beliefs ordered by `updated_at ASC` (oldest first = least-recently touched).

  Attention is reactive — called by Substrate/Driver, not proactive.
  No internal tick loop.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}

  defstruct [
    :agent_id,
    :agent,
    :belief_offset,
    :last_scored_at
  ]

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(%{agent_id: agent_id} = opts) do
    name = {:via, Registry, {Lincoln.AgentRegistry, {agent_id, :attention}}}
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(%{agent_id: agent_id} = opts) do
    %{
      id: {__MODULE__, agent_id},
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @doc """
  Returns the next belief to focus on via round-robin.

  Returns `{:ok, belief, score}` or `{:ok, nil}`.
  """
  def next_thought(pid), do: GenServer.call(pid, :next_thought)

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(%{agent_id: agent_id}) do
    agent = Agents.get_agent!(agent_id)

    state = %__MODULE__{
      agent_id: agent_id,
      agent: agent,
      belief_offset: 0,
      last_scored_at: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:next_thought, _from, state) do
    case next_belief(state) do
      nil ->
        # No belief at current offset — reset and try from beginning
        case next_belief(%{state | belief_offset: 0}) do
          nil ->
            {:reply, {:ok, nil}, %{state | belief_offset: 0, last_scored_at: DateTime.utc_now()}}

          belief ->
            new_state = %{state | belief_offset: 1, last_scored_at: DateTime.utc_now()}

            PubSubBroadcaster.broadcast_attention_update(
              state.agent_id,
              {:next_thought, belief, 0.5}
            )

            {:reply, {:ok, belief, 0.5}, new_state}
        end

      belief ->
        new_offset = state.belief_offset + 1
        new_state = %{state | belief_offset: new_offset, last_scored_at: DateTime.utc_now()}
        PubSubBroadcaster.broadcast_attention_update(state.agent_id, {:next_thought, belief, 0.5})
        {:reply, {:ok, belief, 0.5}, new_state}
    end
  end

  @impl true
  def handle_cast({:notify, _event}, state) do
    {:noreply, state}
  end

  # =============================================================================
  # Private
  # =============================================================================

  defp next_belief(state) do
    beliefs =
      Beliefs.list_beliefs(state.agent,
        limit: 1,
        offset: state.belief_offset,
        order_by: [asc: :updated_at],
        status: "active"
      )

    List.first(beliefs)
  end
end
