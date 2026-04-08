# Lincoln: Thoughts as Processes (Step 1)

## TL;DR

> **Quick Summary**: Replace the Driver GenServer with a Thought GenServer — each thought is a first-class supervised OTP process with its own lifecycle, observability, and interruptibility. This is the move that makes Lincoln categorically different from Sophia and impossible to reproduce in Python.
> 
> **Deliverables**:
> - `Lincoln.Substrate.Thought` GenServer — spawned per-thought, owns its own state and lifecycle
> - `Lincoln.Substrate.ThoughtSupervisor` DynamicSupervisor per agent — manages all running thoughts
> - Substrate wired to spawn Thoughts instead of calling Driver
> - Thought lifecycle events recorded in trajectory (spawn, complete, interrupt, fail)
> - Public API: `Lincoln.Substrate.Thoughts.list/1`, inspect running thoughts
> - `/substrate/thoughts` LiveView — live thought tree dashboard
> - PubSub topics for thought lifecycle events
> 
> **Estimated Effort**: Medium (3-5 days)
> **Parallel Execution**: YES — 4 waves
> **Critical Path**: ThoughtSupervisor → Thought GenServer → Wire Substrate → Dashboard

---

## Context

### Why This Matters
The master plan says: "Each thought is a supervised OTP process spawned by Attention when a candidate is selected. This is the move that makes Lincoln categorically impossible to reproduce in Python."

Sophia's thoughts are nested LLM calls in a Python orchestration loop. Lincoln's thoughts will be first-class supervised OTP processes with lifecycles, interruption, supervision, and concurrency. This is the architectural claim that no other system can make.

### Current State
The Substrate currently calls `Driver.execute(pid, {belief, score})` which fires-and-forgets to a long-lived Driver GenServer. The Driver manages async LLM Tasks internally. This means:
- Thoughts have no individual identity (they're anonymous Tasks inside the Driver)
- Thoughts can't be inspected, interrupted, or observed individually
- There's no process tree showing what's being thought about right now
- Failed thoughts are invisible (Task crashes are silently caught)

### Target State
The Substrate calls `ThoughtSupervisor.spawn_thought(agent_id, belief, score)` which creates a new `Thought` GenServer. The Thought:
- Selects its inference tier (local/Ollama/Claude)
- Executes the cognitive work
- Records results to the belief/memory system
- Broadcasts lifecycle events (spawned, working, completed, failed)
- Terminates when done
- Can be interrupted by Attention when priorities shift

---

## Work Objectives

### Core Objective
Replace anonymous fire-and-forget execution with observable, supervised thought processes that have individual identity and lifecycle.

### Definition of Done
- [ ] `Lincoln.Substrate.Thoughts.list(agent_id)` returns currently running thoughts with their state
- [ ] Starting a substrate and letting it tick spawns Thought processes visible in the dashboard
- [ ] Each thought has: a unique ID, a belief it's thinking about, its tier, its status, its start time
- [ ] Completed thoughts create memories/belief revisions and terminate
- [ ] Failed thoughts are logged in trajectory and terminate (let it crash)
- [ ] `/substrate/thoughts` shows live thought tree updating in real time
- [ ] `mix compile --warnings-as-errors` passes
- [ ] `mix test` passes

### Must NOT Have (Guardrails)
- No interruption logic yet (that's Step 2)
- No child thoughts / tree-of-thought yet (that's Step 3)
- No modifications to Attention scoring
- No modifications to Skeptic or Resonator
- Driver stays in the supervision tree but Substrate no longer calls it directly
- No complex thought state machines — spawn, work, complete/fail, die

---

## Verification Strategy

- **Framework**: ExUnit with Mox
- **Automated tests**: Yes — tests after implementation
- **GenServer testing**: Manual tick injection, `:sys.get_state` for sync

---

## Execution Strategy

```
Wave 1 (Scaffolding — start immediately):
├── Task 1: ThoughtSupervisor DynamicSupervisor [quick]
├── Task 2: PubSub topics for thought lifecycle [quick]
└── Task 3: Thought GenServer module [deep]

Wave 2 (Integration — after Wave 1):
├── Task 4: Wire Substrate to spawn Thoughts [deep]
└── Task 5: Public API (Thoughts.list, inspect) [quick]

Wave 3 (Trajectory + Dashboard — after Wave 2):
├── Task 6: Thought lifecycle events in trajectory [unspecified-high]
└── Task 7: /substrate/thoughts LiveView [visual-engineering]

Wave 4 (Cleanup — after Wave 3):
└── Task 8: Update LEARNINGS.md and README [quick]
```

---

## TODOs

- [x] 1. ThoughtSupervisor — Per-Agent DynamicSupervisor

  **What to do**:
  - Create `lib/lincoln/substrate/thought_supervisor.ex`
  - A DynamicSupervisor that manages all running Thought processes for one agent
  - Register via `{:via, Registry, {Lincoln.AgentRegistry, {agent_id, :thought_supervisor}}}`
  - Add to `AgentSupervisor.init/1` children list (after Driver, before Skeptic)
  - Add `:thought_supervisor` to the `get_process/2` allowed types in `substrate.ex`

  **Must NOT do**:
  - Remove Driver from children (it stays for backward compatibility)

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/agent_supervisor.ex` — add ThoughtSupervisor to children
  - `apps/lincoln/lib/lincoln/substrate.ex` — add `:thought_supervisor` to `get_process/2` guard
  - Context7 DynamicSupervisor: `{DynamicSupervisor, name: via_tuple, strategy: :one_for_one}`

  **Acceptance Criteria**:
  - [ ] `Lincoln.Substrate.get_process(agent_id, :thought_supervisor)` returns `{:ok, pid}`
  - [ ] `DynamicSupervisor.which_children(pid)` returns `[]` (no thoughts spawned yet)
  - [ ] `mix compile --warnings-as-errors` passes

  **Commit**: `feat(thoughts): add ThoughtSupervisor DynamicSupervisor per agent`

- [x] 2. PubSub Topics for Thought Lifecycle

  **What to do**:
  - Add to `lib/lincoln/pub_sub.ex`:
    - `thought_topic(agent_id)` → `"agent:#{agent_id}:thoughts"`
    - `broadcast_thought_event(agent_id, event)` — broadcasts to thought topic + agent topic
  - Events will be: `{:thought_spawned, thought_id, belief, tier}`, `{:thought_completed, thought_id, result}`, `{:thought_failed, thought_id, reason}`

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **References**:
  - `apps/lincoln/lib/lincoln/pub_sub.ex` — follow existing broadcast pattern exactly

  **Commit**: `feat(thoughts): add PubSub topics for thought lifecycle events`

- [x] 3. Thought GenServer

  **What to do**:
  - Create `lib/lincoln/substrate/thought.ex` — the core module
  - Each Thought is a short-lived GenServer that:
    1. Receives `{agent_id, belief, attention_score}` on init
    2. Selects inference tier via `InferenceTier.select_tier/1`
    3. For Level 0: does local computation synchronously in `handle_continue(:execute)`
    4. For Level 1/2: starts async LLM call, receives result in `handle_info`
    5. On completion: persists results (create memory), broadcasts `{:thought_completed, ...}`, terminates normally
    6. On failure: broadcasts `{:thought_failed, ...}`, terminates with reason

  **State struct**:
  ```
  defstruct [
    :id,              # unique thought ID (binary_id)
    :agent_id,
    :belief,          # the belief being thought about
    :attention_score,  # score from Attention
    :tier,            # :local | :ollama | :claude
    :status,          # :initializing | :executing | :awaiting_llm | :completed | :failed
    :result,          # the output (reflection text, belief revision, etc.)
    :started_at,
    :completed_at,
    :parent_id        # nil for now (Step 3 adds child thoughts)
  ]
  ```

  **Key design decisions**:
  - Thought does NOT register in the global Registry (too many short-lived processes). Instead, ThoughtSupervisor tracks them via `DynamicSupervisor.which_children/1`.
  - Thought generates its own UUID on init for identification.
  - Level 0 execution happens synchronously in `handle_continue(:execute)` — the thought completes within a single callback.
  - Level 1/2 execution uses `Task.async` internally — the Thought receives the result in `handle_info` and then terminates.
  - On completion, Thought sends `{:thought_completed, thought_id, result}` to the Substrate process (looked up via Registry).
  - The Thought process terminates with `:normal` after completion, or `{:error, reason}` on failure.

  **Execution logic** (adapted from Driver):
  ```elixir
  # Level 0 — synchronous local computation
  defp execute_local(belief, state) do
    summary = "Contemplating: #{belief.statement} (confidence: #{Float.round(belief.confidence, 2)})"
    %{state | status: :completed, result: summary, completed_at: DateTime.utc_now()}
  end

  # Level 1/2 — async LLM call
  defp execute_llm(belief, tier, state) do
    messages = [
      %{role: "system", content: "You are reflecting on a belief. Be concise (2-3 sentences)."},
      %{role: "user", content: "Reflect on this belief: #{belief.statement}"}
    ]
    task = Task.async(fn -> InferenceTier.execute_at_tier(tier, messages, []) end)
    %{state | status: :awaiting_llm}
    # task result arrives in handle_info
  end
  ```

  **Must NOT do**:
  - No interruption handling (Step 2)
  - No child thought spawning (Step 3)
  - No Registry registration (use ThoughtSupervisor.which_children instead)

  **Recommended Agent Profile**:
  - **Category**: `deep`

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/driver.ex:179-252` — existing execution logic to adapt (do_local_execution, do_async_execution, store_reflection_memory)
  - `apps/lincoln/lib/lincoln/substrate/inference_tier.ex` — `select_tier/2`, `execute_at_tier/3`
  - `apps/lincoln/lib/lincoln/memory.ex` — `create_memory/2` for persisting reflections
  - `apps/lincoln/lib/lincoln/pub_sub.ex` — broadcast thought lifecycle events

  **Acceptance Criteria**:
  - [ ] `Thought.start_link(%{agent_id: id, belief: belief, attention_score: 0.2})` spawns, executes Level 0, terminates
  - [ ] Level 0 thought completes within a single `handle_continue` callback
  - [ ] Level 1/2 thought transitions to `:awaiting_llm` and handles Task result
  - [ ] Completed thought broadcasts `{:thought_completed, thought_id, result}`
  - [ ] Failed thought broadcasts `{:thought_failed, thought_id, reason}`
  - [ ] `mix compile --warnings-as-errors` passes

  **Commit**: `feat(thoughts): add Thought GenServer with lifecycle and tiered execution`

- [x] 4. Wire Substrate to Spawn Thoughts

  **What to do**:
  - Replace `dispatch_to_driver/3` in `substrate.ex` with `spawn_thought/3`
  - `spawn_thought` looks up the ThoughtSupervisor via Registry, calls `DynamicSupervisor.start_child` with a Thought child spec
  - The Thought receives the Substrate's agent_id, belief, and attention_score
  - Substrate no longer calls `Driver.execute/2` directly — thoughts do the work
  - Add `handle_info({:thought_completed, thought_id, result}, state)` to Substrate — updates activation map, logs to trajectory
  - Add `handle_info({:thought_failed, thought_id, reason}, state)` to Substrate — logs failure

  **Must NOT do**:
  - Do NOT remove Driver from supervision tree (backward compat)
  - Do NOT modify Attention

  **Recommended Agent Profile**:
  - **Category**: `deep`

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/substrate.ex:175-186` — replace `dispatch_to_driver`
  - `apps/lincoln/lib/lincoln/substrate/thought.ex` (from Task 3)

  **Acceptance Criteria**:
  - [ ] Each substrate tick spawns a Thought process (when there's a belief to think about)
  - [ ] `DynamicSupervisor.which_children(thought_supervisor_pid)` shows active thoughts
  - [ ] Substrate receives `:thought_completed` messages and updates state
  - [ ] Level 0 thoughts spawn and complete within the tick interval
  - [ ] `mix compile --warnings-as-errors` passes

  **Commit**: `feat(thoughts): wire Substrate to spawn Thoughts instead of calling Driver`

- [x] 5. Public API — List and Inspect Thoughts

  **What to do**:
  - Create `lib/lincoln/substrate/thoughts.ex` — public API module
  - `Thoughts.list(agent_id)` — returns list of `{pid, thought_state}` for all running thoughts
  - `Thoughts.get(agent_id, thought_id)` — finds a specific thought by ID
  - `Thoughts.count(agent_id)` — count of currently running thoughts
  - Implementation: look up ThoughtSupervisor via Registry, call `DynamicSupervisor.which_children/1`, for each child call `GenServer.call(pid, :get_state)`

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **References**:
  - `apps/lincoln/lib/lincoln/substrate.ex` — follow the public API pattern

  **Acceptance Criteria**:
  - [ ] `Thoughts.list(agent_id)` returns running thought states
  - [ ] `Thoughts.count(agent_id)` returns integer
  - [ ] Works correctly when no thoughts are running (returns `[]` / `0`)

  **Commit**: `feat(thoughts): add public API for listing and inspecting thoughts`

- [x] 6. Thought Lifecycle in Trajectory

  **What to do**:
  - When Substrate receives `:thought_completed` or `:thought_failed`, record to trajectory:
    ```
    %{type: :thought_completed, thought_id: id, belief_id: belief.id,
      attention_score: score, tier: tier, duration_ms: duration, result_summary: summary}
    ```
  - Update `Trajectory.summary/2` to include thought counts: total spawned, completed, failed, by tier

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/trajectory.ex` — extend `record_event` and `summary`
  - `apps/lincoln/lib/lincoln/substrate/substrate_event.ex` — schema already has event_data JSONB

  **Commit**: `feat(thoughts): record thought lifecycle events in trajectory`

- [x] 7. `/substrate/thoughts` LiveView

  **What to do**:
  - Create `lib/lincoln_web/live/substrate_thoughts_live.ex` at route `/substrate/thoughts`
  - Subscribe to PubSub thought topic for the active agent
  - Display:
    - Count of currently running thoughts
    - List of active thoughts: ID, belief statement, tier, status, duration
    - Recent completed/failed thoughts (last 20)
    - Each thought shows its belief, score, tier badge, status badge
  - Real-time: new thoughts appear, completed thoughts move to history
  - Add route to router after `/substrate/compare`

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: `["frontend-ui-ux"]`

  **References**:
  - `apps/lincoln/lib/lincoln_web/live/substrate_live.ex` — follow existing dashboard patterns
  - `apps/lincoln/lib/lincoln_web/router.ex` — add route

  **Commit**: `feat(thoughts): add /substrate/thoughts LiveView dashboard`

- [x] 8. Update LEARNINGS.md and README

  **What to do**:
  - Update LEARNINGS.md: mark "Thoughts as processes" as DONE, update Driver audit
  - Update README: add `/substrate/thoughts` to dashboard table, update architecture description to mention thoughts
  - Update Current Limitations: note that interruption (Step 2) and child thoughts (Step 3) are next

  **Recommended Agent Profile**:
  - **Category**: `quick`

  **Commit**: `docs: update README and LEARNINGS for thoughts-as-processes`

---

## Final Verification Wave

> After all 8 tasks, verify the full flow works end-to-end.

- [x] F1. Start agent substrate, verify thoughts spawn on each tick
- [x] F2. Watch `/substrate/thoughts` dashboard — thoughts appear and complete
- [x] F3. Run divergence demo — verify thoughts recorded in trajectory
- [x] F4. `mix compile --warnings-as-errors` + `mix credo --strict` + `mix test`

---

## Commit Strategy

- **T1**: `feat(thoughts): add ThoughtSupervisor DynamicSupervisor per agent`
- **T2**: `feat(thoughts): add PubSub topics for thought lifecycle events`
- **T3**: `feat(thoughts): add Thought GenServer with lifecycle and tiered execution`
- **T4**: `feat(thoughts): wire Substrate to spawn Thoughts instead of calling Driver`
- **T5**: `feat(thoughts): add public API for listing and inspecting thoughts`
- **T6**: `feat(thoughts): record thought lifecycle events in trajectory`
- **T7**: `feat(thoughts): add /substrate/thoughts LiveView dashboard`
- **T8**: `docs: update README and LEARNINGS for thoughts-as-processes`

---

## Success Criteria

### The Test
Start the substrate. Watch `/substrate/thoughts`. See thoughts spawn, work, complete, and die — each one a real supervised OTP process with its own identity. This is something nobody has seen before.

### Verification Commands
```bash
mix compile --warnings-as-errors
mix test
mix credo --strict
```

### The Demo
```elixir
# Start substrate
{:ok, _} = Lincoln.Substrate.start_agent(agent_id)

# Watch thoughts spawn
Lincoln.Substrate.Thoughts.list(agent_id)
# => [%{id: "abc123", belief: "BEAM handles 2M processes", tier: :local, status: :completed, duration_ms: 12}]

# In the browser: http://localhost:4000/substrate/thoughts
# → Live updating list of thoughts spawning, completing, failing
```
