defmodule Lincoln.Substrate.Skeptic do
  @moduledoc """
  Background process that looks for contradictions between beliefs.

  Heuristic detection (no LLM):
  1. Picks a high-confidence active belief
  2. Finds semantically similar beliefs (embedding cosine similarity)
  3. Among similar beliefs, checks for contradiction signals:
     - Different source types with conflicting evidence
     - High confidence on both sides
     - One recently challenged while other is not
  4. Creates belief_relationship with type "contradicts"
  5. Broadcasts skeptic flag for Attention to notice
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}

  @tick_interval 30_000
  @similarity_threshold 0.75

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
    name = {:via, Registry, {Lincoln.AgentRegistry, {agent_id, :skeptic}}}
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
    agent = Agents.get_agent!(agent_id)
    interval = Map.get(opts, :tick_interval, @tick_interval)
    schedule_tick(interval)

    state = %__MODULE__{
      agent_id: agent_id,
      agent: agent,
      tick_count: 0,
      last_tick_at: nil,
      tick_interval: interval
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:tick, state) do
    detect_contradictions(state)

    new_state = %{
      state
      | tick_count: state.tick_count + 1,
        last_tick_at: DateTime.utc_now()
    }

    schedule_tick(state.tick_interval)
    {:noreply, new_state}
  end

  # =============================================================================
  # Private — Tick Logic
  # =============================================================================

  defp detect_contradictions(state) do
    case pick_target_belief(state.agent) do
      nil -> :ok
      belief -> investigate_belief(belief, state)
    end
  end

  defp pick_target_belief(agent) do
    beliefs = Beliefs.list_beliefs(agent, min_confidence: 0.7, limit: 10, status: "active")
    if beliefs == [], do: nil, else: Enum.random(beliefs)
  end

  defp investigate_belief(belief, state) do
    case get_embedding(belief) do
      nil ->
        :ok

      embedding ->
        similar =
          Beliefs.find_similar_beliefs(state.agent, embedding,
            limit: 5,
            threshold: @similarity_threshold
          )

        candidates = Enum.reject(similar, fn b -> b.id == belief.id end)

        Enum.each(candidates, fn candidate ->
          if contradiction_signals?(belief, candidate) do
            maybe_create_contradiction(belief, candidate, state)
          end
        end)
    end
  end

  defp get_embedding(belief) do
    belief.embedding
  end

  defp contradiction_signals?(belief_a, belief_b) do
    both_confident = belief_a.confidence > 0.7 and belief_b.confidence > 0.7
    different_sources = belief_a.source_type != belief_b.source_type

    recently_challenged =
      not is_nil(belief_a.last_challenged_at) or not is_nil(belief_b.last_challenged_at)

    both_confident and (different_sources or recently_challenged)
  end

  defp maybe_create_contradiction(belief_a, belief_b, state) do
    already_exists =
      Beliefs.relationship_exists?(state.agent, belief_a.id, belief_b.id, "contradicts") or
        Beliefs.relationship_exists?(state.agent, belief_b.id, belief_a.id, "contradicts")

    unless already_exists do
      attrs = %{
        agent_id: state.agent_id,
        source_belief_id: belief_a.id,
        target_belief_id: belief_b.id,
        relationship_type: "contradicts",
        confidence: min(belief_a.confidence, belief_b.confidence),
        detected_by: "skeptic",
        evidence:
          "Skeptic detected: both beliefs have confidence > 0.7, different sources or recently challenged"
      }

      case Beliefs.create_relationship(attrs) do
        {:ok, relationship} ->
          Logger.info(
            "[Skeptic #{state.agent_id}] Contradiction detected: #{belief_a.id} <-> #{belief_b.id}"
          )

          PubSubBroadcaster.broadcast_skeptic_flag(
            state.agent_id,
            {:contradiction_detected, relationship, belief_a, belief_b}
          )

        {:error, _} ->
          :ok
      end
    end
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end
end
