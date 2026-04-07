defmodule Lincoln.Substrate.Attention do
  @moduledoc """
  The Attention GenServer decides "what to think about next" using parameterized
  belief scoring. Each agent's `attention_params` produce different belief orderings
  from the same set of beliefs.

  Scoring components:
  - **novelty**: preference for unexplored/recently-created beliefs
  - **tension**: beliefs worth investigating (challenged + confident, or low-confidence + entrenched)
  - **staleness**: beliefs least recently activated
  - **depth**: preference for core beliefs (high confidence + entrenchment)

  Attention is reactive — called by Substrate/Driver, not proactive.
  No internal tick loop.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}

  defstruct [
    :agent_id,
    :agent,
    :attention_params,
    :current_focus_id,
    :last_scored_at,
    activation_map: %{}
  ]

  @source_novelty %{
    "observation" => 1.0,
    "inference" => 0.7,
    "testimony" => 0.5,
    "training" => 0.3
  }

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
  Returns the next belief to focus on, scored by attention parameters.

  Returns `{:ok, belief, score}` or `{:ok, nil}`.
  """
  def next_thought(pid), do: GenServer.call(pid, :next_thought)

  @doc """
  Returns the score breakdown for a specific belief.

  Returns `%{novelty: float, tension: float, staleness: float, depth: float, total: float}`.
  """
  def score_breakdown(pid, belief_id) do
    GenServer.call(pid, {:score_breakdown, belief_id})
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(%{agent_id: agent_id}) do
    agent = Agents.get_agent!(agent_id)
    attention_params = get_attention_params(agent)

    state = %__MODULE__{
      agent_id: agent_id,
      agent: agent,
      attention_params: attention_params,
      current_focus_id: nil,
      last_scored_at: nil,
      activation_map: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:next_thought, _from, state) do
    beliefs = Beliefs.list_beliefs(state.agent, status: "active")

    case beliefs do
      [] ->
        {:reply, {:ok, nil}, %{state | last_scored_at: DateTime.utc_now()}}

      beliefs ->
        now = DateTime.utc_now()
        params = state.attention_params

        scored =
          beliefs
          |> Enum.map(fn belief ->
            score = score_belief(belief, state, params, now)

            score =
              if state.current_focus_id == belief.id do
                min(1.0, score + params.focus_momentum * 0.3)
              else
                score
              end

            {belief, score}
          end)
          |> Enum.sort_by(fn {_belief, score} -> score end, :desc)

        {best_belief, best_score} = hd(scored)

        new_activation_map = Map.put(state.activation_map, best_belief.id, now)

        new_state = %{
          state
          | current_focus_id: best_belief.id,
            last_scored_at: now,
            activation_map: new_activation_map
        }

        PubSubBroadcaster.broadcast_attention_update(
          state.agent_id,
          {:next_thought, best_belief, best_score}
        )

        {:reply, {:ok, best_belief, best_score}, new_state}
    end
  end

  @impl true
  def handle_call({:score_breakdown, belief_id}, _from, state) do
    belief = Beliefs.get_belief!(belief_id)
    now = DateTime.utc_now()
    params = state.attention_params

    novelty = novelty_score(belief, now)
    tension = tension_score(belief, now)
    staleness = staleness_score(belief, state, now)
    depth = depth_score(belief)

    total =
      compute_combined_score(novelty, tension, staleness, depth, params)
      |> maybe_apply_focus_boost(belief.id, state)

    breakdown = %{
      novelty: novelty,
      tension: tension,
      staleness: staleness,
      depth: depth,
      total: total
    }

    {:reply, breakdown, state}
  end

  @impl true
  def handle_cast({:notify, _event}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_cast({:reload_params}, state) do
    agent = Agents.get_agent!(state.agent_id)
    params = get_attention_params(agent)
    {:noreply, %{state | attention_params: params}}
  end

  # =============================================================================
  # Scoring
  # =============================================================================

  defp score_belief(belief, state, params, now) do
    novelty = novelty_score(belief, now)
    tension = tension_score(belief, now)
    staleness = staleness_score(belief, state, now)
    depth = depth_score(belief)

    compute_combined_score(novelty, tension, staleness, depth, params)
  end

  defp compute_combined_score(novelty, tension, staleness, depth, params) do
    score =
      params.novelty_weight * novelty +
        (1 - params.novelty_weight) * depth * params.depth_preference +
        tension * (1 - params.focus_momentum) +
        staleness * params.boredom_decay

    min(1.0, max(0.0, score))
  end

  defp maybe_apply_focus_boost(score, belief_id, state) do
    if state.current_focus_id == belief_id do
      min(1.0, score + state.attention_params.focus_momentum * 0.3)
    else
      score
    end
  end

  defp novelty_score(belief, now) do
    revision_component = (1 - min(belief.revision_count, 10) / 10.0) * 0.5
    source_component = Map.get(@source_novelty, belief.source_type, 0.5) * 0.3
    recency_component = recency_novelty(belief.inserted_at, now) * 0.2

    revision_component + source_component + recency_component
  end

  defp recency_novelty(nil, _now), do: 0.5

  defp recency_novelty(inserted_at, now) do
    age_seconds = DateTime.diff(now, inserted_at, :second)
    one_day = 86_400
    seven_days = 7 * one_day

    cond do
      age_seconds <= one_day -> 1.0
      age_seconds >= seven_days -> 0.0
      true -> 1.0 - (age_seconds - one_day) / (seven_days - one_day)
    end
  end

  defp tension_score(belief, now) do
    challenged = challenged_recently(belief.last_challenged_at, now) * 0.5
    mismatch = confidence_entrenchment_mismatch(belief.confidence, belief.entrenchment) * 0.5

    challenged + mismatch
  end

  defp challenged_recently(nil, _now), do: 0.0

  defp challenged_recently(last_challenged_at, now) do
    age_seconds = DateTime.diff(now, last_challenged_at, :second)
    one_hour = 3_600
    twenty_four_hours = 86_400

    cond do
      age_seconds <= one_hour -> 1.0
      age_seconds >= twenty_four_hours -> 0.0
      true -> 1.0 - (age_seconds - one_hour) / (twenty_four_hours - one_hour)
    end
  end

  defp confidence_entrenchment_mismatch(confidence, entrenchment) do
    abs(confidence - entrenchment / 10.0)
  end

  defp staleness_score(belief, state, now) do
    case Map.get(state.activation_map, belief.id) do
      nil ->
        1.0

      last_activated ->
        age_seconds = DateTime.diff(now, last_activated, :second)
        one_hour = 3_600

        if age_seconds >= one_hour do
          1.0
        else
          age_seconds / one_hour
        end
    end
  end

  defp depth_score(belief) do
    belief.confidence * 0.5 + belief.entrenchment / 20.0 * 0.5
  end

  # =============================================================================
  # Params
  # =============================================================================

  defp get_attention_params(agent) do
    raw = agent.attention_params || %{}

    %{
      novelty_weight: raw["novelty_weight"] || raw[:novelty_weight] || 0.3,
      focus_momentum: raw["focus_momentum"] || raw[:focus_momentum] || 0.5,
      interrupt_threshold: raw["interrupt_threshold"] || raw[:interrupt_threshold] || 0.7,
      boredom_decay: raw["boredom_decay"] || raw[:boredom_decay] || 0.1,
      depth_preference: raw["depth_preference"] || raw[:depth_preference] || 0.5,
      tick_interval_ms: raw["tick_interval_ms"] || raw[:tick_interval_ms] || 5_000
    }
  end
end
