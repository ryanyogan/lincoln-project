defmodule Lincoln.Substrate.Resonator do
  @moduledoc """
  Background process that detects coherence cascades in the belief graph.

  A "cascade" is when 3+ beliefs cluster together — similar content + recent activity.
  This is the mechanism that makes Lincoln "get hooked on a topic":
  coherent belief clusters generate resonator flags that Attention weights more heavily.

  Detection is crude in v1 — pure heuristic, no LLM, no embeddings.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}

  @tick_interval 60_000
  @min_cluster_size 3
  @cascade_window_hours 1

  defstruct [
    :agent_id,
    :agent,
    :tick_count,
    :last_tick_at,
    :tick_interval
  ]

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(%{agent_id: agent_id} = opts) do
    name = {:via, Registry, {Lincoln.AgentRegistry, {agent_id, :resonator}}}
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

  @doc "Returns the full state struct."
  def get_state(pid), do: GenServer.call(pid, :get_state)

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(%{agent_id: agent_id} = opts) do
    interval = Map.get(opts, :tick_interval, @tick_interval)

    state = %__MODULE__{
      agent_id: agent_id,
      agent: nil,
      tick_count: 0,
      last_tick_at: nil,
      tick_interval: interval
    }

    {:ok, state, {:continue, :load_state}}
  end

  @impl true
  def handle_continue(:load_state, state) do
    agent = Agents.get_agent!(state.agent_id)
    schedule_tick(state.tick_interval)

    {:noreply, %{state | agent: agent}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:tick, state) do
    detect_cascades(state)

    new_state = %{
      state
      | tick_count: state.tick_count + 1,
        last_tick_at: DateTime.utc_now()
    }

    schedule_tick(state.tick_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    Logger.info("[Resonator #{state.agent_id}] Terminating: #{inspect(reason)}")
    :ok
  end

  # =============================================================================
  # Private — Tick Logic
  # =============================================================================

  defp detect_cascades(state) do
    beliefs = Beliefs.list_beliefs(state.agent, status: "active")

    if Enum.count(beliefs) < @min_cluster_size do
      :ok
    else
      beliefs
      |> Enum.group_by(& &1.source_type)
      |> Enum.each(fn {_type, cluster_beliefs} ->
        if Enum.count(cluster_beliefs) >= @min_cluster_size and cascade_active?(cluster_beliefs) do
          process_cascade(cluster_beliefs, state)
        end
      end)
    end
  end

  defp cascade_active?(beliefs) do
    now = DateTime.utc_now()
    window = @cascade_window_hours * 3600

    recently_active_count =
      Enum.count(beliefs, fn belief ->
        age = DateTime.diff(now, belief.updated_at, :second)
        age <= window
      end)

    recently_active_count >= @min_cluster_size
  end

  defp process_cascade(cluster_beliefs, state) do
    avg_confidence =
      cluster_beliefs
      |> Enum.map(& &1.confidence)
      |> then(fn confs -> Enum.sum(confs) / length(confs) end)

    cascade_score = length(cluster_beliefs) * avg_confidence

    pairs = for a <- cluster_beliefs, b <- cluster_beliefs, a.id < b.id, do: {a, b}

    new_relationships =
      pairs
      |> Enum.filter(fn {a, b} ->
        not Beliefs.relationship_exists?(state.agent, a.id, b.id, "supports")
      end)
      |> Enum.map(fn {a, b} ->
        Beliefs.create_relationship(%{
          agent_id: state.agent_id,
          source_belief_id: a.id,
          target_belief_id: b.id,
          relationship_type: "supports",
          confidence: avg_confidence,
          detected_by: "resonator",
          evidence:
            "Resonator cascade: #{length(cluster_beliefs)} beliefs of same source type recently active"
        })
      end)
      |> Enum.count(fn result -> match?({:ok, _}, result) end)

    if new_relationships > 0 do
      Logger.info(
        "[Resonator #{state.agent_id}] Cascade detected: #{length(cluster_beliefs)} beliefs, score #{Float.round(cascade_score, 2)}"
      )

      PubSubBroadcaster.broadcast_resonator_flag(
        state.agent_id,
        {:cascade_detected,
         %{
           belief_ids: Enum.map(cluster_beliefs, & &1.id),
           cascade_score: cascade_score,
           cluster_size: length(cluster_beliefs),
           relationships_created: new_relationships
         }}
      )
    end
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
