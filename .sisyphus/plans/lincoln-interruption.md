# Lincoln: Thought Interruption (Step 2)

## TL;DR

> **Quick Summary**: When Attention scores a belief high enough to exceed the running thought's `interrupt_threshold`, the Substrate interrupts the current thought and spawns a new one for the higher-priority belief. The `interrupt_threshold` parameter IS the cognitive style — focused Lincoln resists interruption, butterfly Lincoln drops everything.
>
> **Deliverables**:
> - `Thought.interrupt/1` — sends `:interrupt` to a running thought, it terminates gracefully
> - Substrate tick logic updated: only spawn if no thought running, OR interrupt if score exceeds threshold
> - `interrupt_threshold` read from agent's `attention_params` (already exists in schema)
> - `:thought_interrupted` PubSub event + dashboard update
> - Tests verifying interrupt behavior with focused vs butterfly params
>
> **Estimated Effort**: Small (1-2 days)
> **Parallel Execution**: YES — 3 waves
> **Critical Path**: Thought interrupt handler → Substrate interruption logic → Dashboard

---

## Context

### Why This Matters
The master plan says: *"The interrupt-handling policy is itself part of the cognitive style — focused Lincolns resist interruption, butterfly Lincolns drop everything. This is what attention deficit looks like as an architectural property rather than a metaphor."*

Right now, the Substrate spawns a new Thought on every tick regardless of whether one is already running. This means thoughts pile up and there's no priority scheduling. Interruption makes the cognitive style parameters DO something visible.

### Current State
- Substrate calls `spawn_thought` on every tick, even if a thought is already running
- `interrupt_threshold` exists in `attention_params` schema but is only used in Attention scoring bonuses
- No `:interrupt` message handling in Thought
- Thoughts don't know they can be interrupted

### Target State
Every tick:
1. Attention returns `{belief, score}`
2. Substrate checks if a Thought is currently running
3. **If no thought running** → spawn normally
4. **If thought running AND score > interrupt_threshold** → interrupt current thought, spawn new one
5. **If thought running AND score ≤ interrupt_threshold** → skip (let current thought finish)

Result: focused Lincoln (interrupt_threshold: 0.8) almost never interrupts — thoughts run to completion. Butterfly Lincoln (interrupt_threshold: 0.3) interrupts constantly — attention jumps to whatever scores highest. ADHD-like Lincoln (interrupt_threshold: 0.9, high score bursts) rarely interrupts but when it does, the new thing MUST be very important.

---

## Work Objectives

### Definition of Done
- [ ] `Thought.interrupt(pid)` sends `:interrupt`, thought terminates with `:interrupted` reason
- [ ] Thought broadcasts `{:thought_interrupted, id, :preempted}` on interrupt
- [ ] Substrate only spawns new thought when: no thought running, OR score > interrupt_threshold
- [ ] `interrupt_threshold` read from `state.agent.attention_params`
- [ ] `/substrate/thoughts` shows interrupted thoughts in history with "interrupted" badge
- [ ] `mix compile --warnings-as-errors` passes

### Must NOT Have (Guardrails)
- No changes to Attention scoring (that's already wired)
- No changes to Skeptic, Resonator, or any other substrate module
- No new migrations
- No complex interrupt state machines — interrupt means stop, broadcast, done
- No "interrupt queue" or retry logic — if interrupted, it's gone

---

## Execution Strategy

```
Wave 1 (Thought interrupt handler):
└── Task 1: Add :interrupt handling to Thought GenServer [quick]

Wave 2 (Substrate wiring):
└── Task 2: Wire interruption logic into Substrate tick [deep]

Wave 3 (Dashboard + docs):
├── Task 3: Handle :thought_interrupted in SubstrateThoughtsLive [quick]
└── Task 4: Update LEARNINGS.md [quick]
```

---

## TODOs

- [x] 1. Add `:interrupt` Handling to Thought GenServer

  **What to do**:
  Add to `apps/lincoln/lib/lincoln/substrate/thought.ex`:
  1. Public API: `def interrupt(pid), do: GenServer.cast(pid, :interrupt)`
  2. Handle the cast:
  ```elixir
  @impl true
  def handle_cast(:interrupt, state) do
    Logger.debug("[Thought #{state.id}] Interrupted")
    PubSubBroadcaster.broadcast_thought_event(
      state.agent_id,
      {:thought_interrupted, state.id, :preempted}
    )
    {:stop, :interrupted, state}
  end
  ```
  3. Update `terminate/2` to log the interruption reason clearly:
  ```elixir
  @impl true
  def terminate(:interrupted, state) do
    Logger.info("[Thought #{state.id}] Terminated: interrupted (preempted by higher-priority belief)")
    :ok
  end
  def terminate(reason, state) do
    Logger.debug("[Thought #{state.id}] Terminating: #{inspect(reason)}")
    :ok
  end
  ```

  **Key**: `:interrupted` is a valid GenServer stop reason (not `:normal` or `:shutdown`). Since `restart: :temporary`, DynamicSupervisor will NOT restart it. The ThoughtSupervisor just removes it cleanly.

  **Acceptance Criteria**:
  - [ ] `Thought.interrupt(pid)` → thought broadcasts `:thought_interrupted` and terminates
  - [ ] Interrupted thought does NOT get restarted (restart: :temporary ensures this)
  - [ ] `mix compile --warnings-as-errors` passes

  **Recommended Agent Profile**: `quick`
  **Commit**: `feat(interrupt): add :interrupt handling to Thought GenServer`

- [x] 2. Wire Interruption Logic in Substrate Tick

  **What to do**:
  Rewrite `spawn_thought/3` in `apps/lincoln/lib/lincoln/substrate/substrate.ex` to implement the interruption policy:

  ```elixir
  defp spawn_thought(_state, nil, _score), do: :no_belief

  defp spawn_thought(state, belief, score) do
    interrupt_threshold = get_interrupt_threshold(state)

    case ThoughtSupervisor.list_children(state.agent_id) do
      [] ->
        # No thought running — spawn freely
        do_spawn_thought(state, belief, score)

      [{_id, pid, _type, _modules} | _rest] when is_pid(pid) ->
        # A thought is running — check interrupt_threshold
        if score >= interrupt_threshold do
          # High-priority belief — interrupt current thought and spawn new one
          Logger.debug("[Substrate #{state.agent_id}] Interrupting thought (score #{Float.round(score, 2)} >= threshold #{Float.round(interrupt_threshold, 2)})")
          Lincoln.Substrate.Thought.interrupt(pid)
          do_spawn_thought(state, belief, score)
        else
          # Lower priority — let current thought finish
          Logger.debug("[Substrate #{state.agent_id}] Skipping spawn (score #{Float.round(score, 2)} < threshold #{Float.round(interrupt_threshold, 2)})")
          :thought_running
        end

      _ ->
        do_spawn_thought(state, belief, score)
    end
  end

  defp do_spawn_thought(state, belief, score) do
    thought_opts = %{
      agent_id: state.agent_id,
      belief: belief,
      attention_score: score || 0.0
    }

    case ThoughtSupervisor.spawn_thought(state.agent_id, thought_opts) do
      {:ok, _pid} ->
        Lincoln.Substrate.InferenceTier.select_tier(score || 0.0)
      {:error, reason} ->
        Logger.debug("[Substrate #{state.agent_id}] Could not spawn thought: #{inspect(reason)}")
        nil
    end
  end

  defp get_interrupt_threshold(state) do
    params = state.agent && state.agent.attention_params
    # attention_params is stored as string-keyed map from DB
    raw = (params && Map.get(params, "interrupt_threshold")) ||
          (params && Map.get(params, :interrupt_threshold)) ||
          0.7  # default

    # Ensure it's a float
    case raw do
      f when is_float(f) -> f
      i when is_integer(i) -> i / 1.0
      _ -> 0.7
    end
  end
  ```

  **Acceptance Criteria**:
  - [ ] With `interrupt_threshold: 0.9` (focused): thought almost never interrupted
  - [ ] With `interrupt_threshold: 0.2` (butterfly): thought interrupted by any mid-scored belief
  - [ ] `ThoughtSupervisor.list_children` correctly detects running thoughts
  - [ ] `mix compile --warnings-as-errors` passes

  **Recommended Agent Profile**: `deep`

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/substrate.ex` — `spawn_thought/3` at line 201 (replace entirely)
  - `apps/lincoln/lib/lincoln/substrate/thought_supervisor.ex` — `list_children/1` returns DynamicSupervisor.which_children
  - `apps/lincoln/lib/lincoln/substrate/thought.ex` — `Thought.interrupt/1` from Task 1

  **Commit**: `feat(interrupt): wire interruption logic into Substrate tick with threshold`

- [ ] 3. Handle `:thought_interrupted` in SubstrateThoughtsLive

  **What to do**:
  In `apps/lincoln_web/live/substrate_thoughts_live.ex`, add handler:
  ```elixir
  def handle_info({:thought_interrupted, thought_id, reason}, socket) do
    {interrupted, remaining} =
      Enum.split_with(socket.assigns.active_thoughts, fn t -> t.id == thought_id end)

    history_entry =
      case interrupted do
        [t | _] -> %{t | status: :interrupted, result: "Interrupted: #{reason}", completed_at: DateTime.utc_now()}
        [] ->
          %{id: thought_id, status: :interrupted, result: "Interrupted",
            belief_statement: "Unknown", tier: :local,
            started_at: DateTime.utc_now(), completed_at: DateTime.utc_now()}
      end

    history = [history_entry | socket.assigns.thought_history] |> Enum.take(@max_history)

    {:noreply, socket
      |> assign(:active_thoughts, remaining)
      |> assign(:thought_history, history)}
  end
  ```

  Also add to the `status_badge/1` helper:
  ```elixir
  defp status_badge(:interrupted), do: {"bg-warning/20 text-warning", "interrupted"}
  ```

  **Acceptance Criteria**:
  - [ ] Interrupted thoughts appear in history with "interrupted" badge (yellow)
  - [ ] `mix compile --warnings-as-errors` passes

  **Recommended Agent Profile**: `quick`
  **Commit**: `feat(interrupt): handle :thought_interrupted in thoughts dashboard`

- [ ] 4. Update LEARNINGS.md

  **What to do**:
  - Mark "Thought interruption (Step 2)" as DONE in LEARNINGS.md
  - Note that `interrupt_threshold` now has real behavioral effect
  - Note: Agent's `attention_params` must be loaded/fresh for interruption to work correctly (stale agent struct is a known limitation)

  **Recommended Agent Profile**: `quick`
  **Commit**: `docs: update LEARNINGS for thought interruption`

---

## Final Verification

- [ ] F1. `mix compile --warnings-as-errors` — zero warnings
- [ ] F2. `mix credo --strict` — no regressions (stays at 36)
- [ ] F3. Manual: start substrate, observe `/substrate/thoughts`, seed a high-score event, watch interruption

---

## The Demo After Step 2

```elixir
# Start focused Lincoln (interrupt_threshold: 0.8)
Lincoln.Agents.update_agent(agent, %{
  attention_params: Lincoln.Substrate.AttentionParams.focused()
})
Lincoln.Substrate.start_agent(agent.id)
# → Watch /substrate/thoughts: thoughts run to completion, rarely interrupted

# Switch to butterfly (interrupt_threshold: 0.3)
Lincoln.Agents.update_agent(agent, %{
  attention_params: Lincoln.Substrate.AttentionParams.butterfly()
})
# Notify Attention to reload
{:ok, pid} = Lincoln.Substrate.get_process(agent.id, :attention)
GenServer.cast(pid, {:reload_params})
# → Watch /substrate/thoughts: thoughts constantly preempted, attention jumps around
```

Two Lincoln instances. Different interrupt thresholds. Visibly different behavior. That's the demo.
