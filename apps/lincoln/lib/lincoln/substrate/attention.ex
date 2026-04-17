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
  - **contradiction_bonus**: tension boost from Skeptic-detected contradictions (scaled by `interrupt_threshold`)
  - **cascade_bonus**: interest boost from Resonator-detected support clusters (scaled by `novelty_weight`)

  Attention is reactive — called by Substrate/Driver, not proactive.
  No internal tick loop.
  """

  use GenServer
  require Logger

  alias Lincoln.{Agents, Beliefs, PubSubBroadcaster}
  alias Lincoln.Substrate.{AttentionParams, CognitiveImpulse}

  @max_focus_history 20

  defstruct [
    :agent_id,
    :agent,
    :attention_params,
    :current_focus_id,
    :last_scored_at,
    activation_map: %{},
    impulse_state: CognitiveImpulse.initial_state(),
    recent_focus_ids: []
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

  @max_trajectory_candidates 5

  @doc """
  Returns the next belief to focus on, scored by attention parameters.

  Returns `{:ok, belief, score, scoring_detail}` or `{:ok, nil}`.
  The `scoring_detail` map contains the top candidates with per-component
  score breakdowns and the active attention params.
  """
  def next_thought(pid), do: GenServer.call(pid, :next_thought)

  @doc """
  Lightweight scoring for idle ticks — skips relationship queries and
  does not update activation_map or broadcast. Returns the same shape
  as `next_thought/1`.
  """
  def idle_score(pid), do: GenServer.call(pid, :idle_score)

  @doc """
  Returns the score breakdown for a specific belief.

  Returns `%{novelty: float, tension: float, staleness: float, depth: float,
  contradiction_bonus: float, cascade_bonus: float, total: float}`.
  """
  def score_breakdown(pid, belief_id) do
    GenServer.call(pid, {:score_breakdown, belief_id})
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(%{agent_id: agent_id}) do
    state = %__MODULE__{
      agent_id: agent_id,
      agent: nil,
      attention_params: nil,
      current_focus_id: nil,
      last_scored_at: nil,
      activation_map: %{}
    }

    {:ok, state, {:continue, :load_state}}
  end

  @impl true
  def handle_continue(:load_state, state) do
    agent = Agents.get_agent!(state.agent_id)
    attention_params = get_attention_params(agent)

    {:noreply, %{state | agent: agent, attention_params: attention_params}}
  end

  @impl true
  def handle_call(:next_thought, _from, state) do
    beliefs = Beliefs.list_beliefs(state.agent, status: "active")

    now = DateTime.utc_now()

    # Include cognitive impulses alongside real beliefs
    impulses = CognitiveImpulse.candidates(state.agent, state.impulse_state, now)
    all_candidates = beliefs ++ impulses

    case all_candidates do
      [] ->
        {:reply, {:ok, nil}, %{state | last_scored_at: now}}

      candidates ->
        params = state.attention_params
        all_relationships = Beliefs.find_all_relationships(state.agent)

        scored =
          candidates
          |> Enum.map(fn belief ->
            {score, components} =
              score_with_focus_detailed(belief, state, params, now, all_relationships)

            {belief, score, components}
          end)
          |> Enum.sort_by(fn {_belief, score, _components} -> score end, :desc)

        {best_belief, best_score, _best_components} = hd(scored)

        # Select thought type based on cognitive style and belief state
        thought_type = select_thought_type(params, best_belief)

        scoring_detail =
          build_scoring_detail(scored, params) |> Map.put(:thought_type, thought_type)

        impulse_state = update_impulse_cooldown(state.impulse_state, best_belief.id, now)
        new_activation_map = update_activation_map(state.activation_map, best_belief.id, now)

        # Track recent focus for monotony detection
        recent = [best_belief.id | state.recent_focus_ids] |> Enum.take(@max_focus_history)

        new_state = %{
          state
          | current_focus_id: best_belief.id,
            last_scored_at: now,
            activation_map: new_activation_map,
            impulse_state: impulse_state,
            recent_focus_ids: recent
        }

        PubSubBroadcaster.broadcast_attention_update(
          state.agent_id,
          {:next_thought, best_belief, best_score}
        )

        {:reply, {:ok, best_belief, best_score, scoring_detail}, new_state}
    end
  end

  @impl true
  def handle_call(:idle_score, _from, state) do
    beliefs = Beliefs.list_beliefs(state.agent, status: "active")

    case beliefs do
      [] ->
        {:reply, {:ok, nil}, state}

      beliefs ->
        now = DateTime.utc_now()
        params = state.attention_params

        # Skip relationship query — pass empty list for lightweight scoring
        scored =
          beliefs
          |> Enum.map(fn belief ->
            {score, components} =
              score_with_focus_detailed(belief, state, params, now, [])

            {belief, score, components}
          end)
          |> Enum.sort_by(fn {_belief, score, _components} -> score end, :desc)

        {best_belief, best_score, _best_components} = hd(scored)

        scoring_detail = build_scoring_detail(scored, params)

        # Update activation_map so staleness decays for the focused belief
        new_activation_map =
          state.activation_map
          |> Map.put(best_belief.id, now)
          |> bound_map(500)

        {:reply, {:ok, best_belief, best_score, scoring_detail},
         %{state | activation_map: new_activation_map, last_scored_at: now}}
    end
  end

  @impl true
  def handle_call({:score_breakdown, belief_id}, _from, state) do
    belief = Beliefs.get_belief!(belief_id)
    now = DateTime.utc_now()
    params = state.attention_params
    belief_rels = Beliefs.find_relationships(state.agent, belief_id)

    novelty = novelty_score(belief, state, now)
    tension = tension_score(belief, now)
    staleness = staleness_score(belief, state, now)
    depth = depth_score(belief)

    cb = contradiction_bonus(belief.id, belief_rels, params)
    csb = cascade_bonus(belief.id, belief_rels, params)

    base = compute_combined_score(novelty, tension, staleness, depth, params)

    total =
      min(1.0, max(0.0, base + cb + csb))
      |> maybe_apply_focus_boost(belief.id, state)

    breakdown = %{
      novelty: novelty,
      tension: tension,
      staleness: staleness,
      depth: depth,
      contradiction_bonus: cb,
      cascade_bonus: csb,
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

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    Logger.info("[Attention #{state.agent_id}] Terminating: #{inspect(reason)}")
    :ok
  end

  # =============================================================================
  # Impulse & Activation Helpers
  # =============================================================================

  defp update_impulse_cooldown(impulse_state, belief_id, now) do
    if CognitiveImpulse.impulse?(belief_id) do
      key = :"last_#{CognitiveImpulse.impulse_type(belief_id)}_at"

      if Map.has_key?(impulse_state, key) do
        Map.put(impulse_state, key, now)
      else
        impulse_state
      end
    else
      impulse_state
    end
  end

  defp update_activation_map(activation_map, belief_id, now) do
    if CognitiveImpulse.impulse?(belief_id) do
      activation_map
    else
      activation_map
      |> Map.put(belief_id, now)
      |> bound_map(500)
    end
  end

  # =============================================================================
  # Thought Type Selection
  # =============================================================================

  defp select_thought_type(params, belief) do
    base_type = AttentionParams.select_thought_type(params)

    # Adjust based on belief state
    cond do
      belief.confidence >= 0.9 and :rand.uniform() < 0.4 -> :critique
      belief.entrenchment <= 2 and :rand.uniform() < 0.3 -> :question
      belief.revision_count == 0 and :rand.uniform() < 0.3 -> :connect
      true -> base_type
    end
  rescue
    _ -> :elaborate
  end

  # =============================================================================
  # Scoring
  # =============================================================================

  defp score_with_focus_detailed(belief, state, params, now, all_relationships) do
    {base_score, components} =
      score_belief_detailed(belief, state, params, now, all_relationships)

    # Focus momentum boost
    focus_boost =
      if state.current_focus_id == belief.id,
        do: params.focus_momentum * 0.3,
        else: 0.0

    # Monotony penalty — prevent perseveration on the same belief
    monotony = monotony_penalty(belief.id, state.recent_focus_ids)

    final_score = min(1.0, max(0.0, base_score + focus_boost - monotony))

    extra = %{focus_boost: focus_boost, monotony_penalty: monotony, final_score: final_score}
    {final_score, Map.merge(components, extra)}
  end

  defp score_belief_detailed(belief, state, params, now, belief_rels) do
    novelty = novelty_score(belief, state, now)
    tension = tension_score(belief, now)
    staleness = staleness_score(belief, state, now)
    depth = depth_score(belief)

    base = compute_combined_score(novelty, tension, staleness, depth, params)

    cb = contradiction_bonus(belief.id, belief_rels, params)
    csb = cascade_bonus(belief.id, belief_rels, params)

    score = min(1.0, max(0.0, base + cb + csb))

    components = %{
      novelty: novelty,
      tension: tension,
      staleness: staleness,
      depth: depth,
      contradiction_bonus: cb,
      cascade_bonus: csb,
      base_score: score
    }

    {score, components}
  end

  defp compute_combined_score(novelty, tension, staleness, depth, params) do
    # Weighted average — weights sum to 1.0, so the score naturally stays in [0, 1]
    # This prevents saturation where all beliefs clamp to 1.0
    nw = params.novelty_weight
    dw = (1 - nw) * params.depth_preference
    tw = (1 - params.focus_momentum) * 0.5
    sw = params.boredom_decay

    total_weight = nw + dw + tw + sw
    total_weight = if total_weight == 0, do: 1.0, else: total_weight

    score =
      (nw * novelty + dw * depth + tw * tension + sw * staleness) /
        total_weight

    min(1.0, max(0.0, score))
  end

  defp maybe_apply_focus_boost(score, belief_id, state) do
    if state.current_focus_id == belief_id do
      min(1.0, score + state.attention_params.focus_momentum * 0.3)
    else
      score
    end
  end

  defp novelty_score(belief, state, now) do
    revision_component = (1 - min(belief.revision_count, 10) / 10.0) * 0.4
    source_component = Map.get(@source_novelty, belief.source_type, 0.5) * 0.2
    recency_component = recency_novelty(belief.inserted_at, now) * 0.15
    fatigue_component = activation_fatigue(belief.id, state, now) * 0.25

    revision_component + source_component + recency_component + fatigue_component
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

  defp activation_fatigue(belief_id, state, now) do
    case Map.get(state.activation_map, belief_id) do
      nil ->
        1.0

      last_activated ->
        age_seconds = DateTime.diff(now, last_activated, :second)
        recovery_window = 600

        if age_seconds >= recovery_window do
          1.0
        else
          age_seconds / recovery_window
        end
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
        staleness_window = 300

        if age_seconds >= staleness_window do
          1.0
        else
          age_seconds / staleness_window
        end
    end
  end

  defp depth_score(belief) do
    raw = belief.confidence * 0.5 + belief.entrenchment / 20.0 * 0.5

    # Settled beliefs are boring — like how you don't think about gravity
    # c=1.0 + e>=5 → heavy penalty. The belief is known. Move on.
    settled_penalty =
      if belief.confidence >= 0.9 and belief.entrenchment >= 5 do
        0.6
      else
        settled = belief.confidence * (belief.entrenchment / 10.0)
        settled * settled * 0.4
      end

    # Over-revised beliefs have diminishing returns
    revision_penalty = min(belief.revision_count / 15.0, 0.5) * 0.2

    max(0.0, raw - settled_penalty - revision_penalty)
  end

  # Monotony penalty: how many of the last N thoughts were about this belief?
  # After 5 consecutive same-belief thoughts, penalty starts.
  # After 10, it's significant. After 15+, it's overwhelming.
  defp monotony_penalty(_belief_id, []), do: 0.0

  defp monotony_penalty(belief_id, recent_focus_ids) do
    consecutive = count_consecutive(belief_id, recent_focus_ids)

    cond do
      consecutive >= 15 -> 0.8
      consecutive >= 10 -> 0.5
      consecutive >= 5 -> 0.3
      consecutive >= 3 -> 0.1
      true -> 0.0
    end
  end

  defp count_consecutive(target, list) do
    Enum.reduce_while(list, 0, fn id, count ->
      if id == target, do: {:cont, count + 1}, else: {:halt, count}
    end)
  end

  defp contradiction_bonus(_belief_id, [], _params), do: 0.0

  defp contradiction_bonus(belief_id, belief_rels, params) do
    contradictions =
      Enum.filter(belief_rels, fn r ->
        r.relationship_type == "contradicts" and
          (r.source_belief_id == belief_id or r.target_belief_id == belief_id)
      end)

    case contradictions do
      [] ->
        0.0

      confs ->
        avg_confidence =
          confs
          |> Enum.map(& &1.confidence)
          |> then(fn vals -> Enum.sum(vals) / length(vals) end)

        params.interrupt_threshold * avg_confidence * 0.4
    end
  end

  defp cascade_bonus(_belief_id, [], _params), do: 0.0

  defp cascade_bonus(belief_id, belief_rels, params) do
    supports =
      Enum.filter(belief_rels, fn r ->
        r.relationship_type == "supports" and
          (r.source_belief_id == belief_id or r.target_belief_id == belief_id)
      end)

    case supports do
      [] ->
        0.0

      matched ->
        support_count = length(matched)
        params.novelty_weight * min(support_count / 5.0, 1.0) * 0.3
    end
  end

  # =============================================================================
  # Trajectory Detail
  # =============================================================================

  defp build_scoring_detail(scored, params) do
    top_candidates =
      scored
      |> Enum.take(@max_trajectory_candidates)
      |> Enum.with_index(1)
      |> Enum.map(fn {{belief, _score, components}, rank} ->
        %{
          belief_id: belief.id,
          statement: String.slice(belief.statement || "", 0, 80),
          components: components,
          rank: rank
        }
      end)

    %{
      params: params,
      candidate_count: length(scored),
      top_candidates: top_candidates
    }
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp bound_map(map, max_size) when map_size(map) <= max_size, do: map

  defp bound_map(map, max_size) do
    map
    |> Enum.sort_by(fn {_k, v} -> v end, DateTime)
    |> Enum.take(max_size)
    |> Map.new()
  end

  # =============================================================================
  # Params
  # =============================================================================

  defp get_attention_params(agent) do
    raw = agent.attention_params || %{}
    defaults = AttentionParams.default()

    Map.new(defaults, fn {key, default_val} ->
      {key, raw[to_string(key)] || raw[key] || default_val}
    end)
  end
end
