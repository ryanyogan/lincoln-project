# Lincoln: Continuous Cognitive Substrate

## TL;DR

> **Quick Summary**: Transform Lincoln from a stateless job-queue system (Oban workers that reconstruct context every cycle) into a continuously-running cognitive substrate (long-lived GenServer processes with persistent in-memory state and tick loops). Build alongside the existing system — nothing is removed, only new code paths are added.
> 
> **Deliverables**:
> - 5 supervised GenServer processes per agent (Substrate, Attention, Driver, Skeptic, Resonator) with per-agent DynamicSupervisor + Registry
> - Three-tier inference: pure computation (free) → Ollama local model (cheap) → Claude (expensive, high-attention only)
> - Parameterized attention system where different parameters produce visibly different cognitive behavior
> - Belief relationship graph with typed edges for Skeptic/Resonator traversal
> - Dashboard extensions showing real-time cognitive state + side-by-side comparison view
> - Divergence demo: two instances with different parameters producing different trajectories on the same input
> 
> **Estimated Effort**: Large (6-8 weeks)
> **Parallel Execution**: YES — 8 waves
> **Critical Path**: DynamicSupervisor → Substrate GenServer → Per-agent Supervisor → Parameterized Attention → Skeptic/Resonator → Divergence Demo

---

## Context

### Original Request
Build a continuously-running cognitive substrate on the BEAM that exhibits four properties: (1) continuity of process, (2) self-generated next actions, (3) differential interest formation, (4) tunable attention / cognitive style. Follow a 4-step build sequence from the architecture sketch. Reconcile against the existing 6-iteration codebase rather than treating as greenfield.

### Interview Summary
**Key Discussions**:
- **Oban disposition**: Organic migration — build GenServer processes alongside Oban. Let workers migrate naturally as their logic moves into the 5 core processes. Some workers may stay if they're naturally job-shaped.
- **Conversation model**: Conversation as substrate input — chat messages are events sent to the Substrate. No separate "chat mode." Talking to Lincoln is sending a message to a process that was already running. Synchronous response path stays for UX, with async Substrate notification alongside.
- **Inference tiering**: Three levels — Level 0 (pure computation on belief graph, free, most ticks), Level 1 (Ollama local 7-14B model, cheap), Level 2 (Claude, expensive, high-attention only).
- **Multi-instance**: Per-agent DynamicSupervisor + Registry from Step 1. Each agent gets its own supervision tree.
- **App structure**: Keep monolith — don't split to umbrella.

**Research Findings**:
- `AutonomousLearningWorker` (680 lines) is the proto-Substrate — already does 30s tick cycles, budget checking, session lifecycle. This informs the GenServer design.
- `learning/belief_formation.ex` already has attention-like scoring: `learning_priority`, `revision_urgency`, `metacognitive_flags`, `decision_weight`. The Attention process builds on these, doesn't reinvent them.
- Existing adapter pattern (`adapters/llm.ex`) has Behaviour + implementation + Mock. Ollama adapter follows this exactly.
- PubSub has agent-scoped topics (`agent:{id}:subtopic`). New processes add `:substrate`, `:attention`, `:driver`, `:skeptic`, `:resonator` topics.
- Ecto documents self-referential many_to_many with join table pattern — perfect for `belief_relationships`.
- pgvector HNSW index is better than existing IVFFlat for dynamic belief graph (frequent inserts).
- Ollama REST API at `localhost:11434` — `POST /api/chat` for inference, `GET /api/tags` for model listing, OpenAI-compatible at `/v1/chat/completions`.

### Metis Review
**Identified Gaps** (addressed):
- **Inter-process communication**: Defaulted to PubSub for loose coupling (matches existing patterns). Substrate receives direct `GenServer.cast` for events. Skeptic/Resonator write flags to DB table, Attention reads on next tick.
- **State persistence**: DB-derived state (matching AutonomousLearningWorker pattern). GenServer state is a working cache of what's in Postgres. On crash, state is reconstructed from DB. Minimize in-memory-only state.
- **AutonomousLearningWorker fate**: Stays running in Steps 1-2 (parallel system). Becomes a Substrate client in Step 2 (sends events instead of operating independently). Absorbed into Driver logic in Step 3.
- **Tick rate and LLM blocking**: 5-second configurable tick interval. LLM calls are async via `Task.async` under a `Task.Supervisor`. Results arrive as messages handled in `handle_info`. Driver moves on to next tick regardless.
- **ConversationHandler integration**: Synchronous response path stays intact (users need fast responses). New code path sends `:new_message` event to Substrate via `GenServer.cast` alongside the existing pipeline. No modification of the 1,448-line handler in Step 1.
- **DB connection pool**: Size pool proportional to max concurrent agents × tick frequency. Note: default dev pool of 10 may need increase.
- **Embedding service fallback**: Attention scoring must work without embeddings — fallback to recency + entrenchment + explicit flags only.
- **Test infrastructure**: Design GenServers to be testable without real timers. Inject tick triggers via `send(pid, :tick)` in tests, not `Process.send_after`.

---

## Work Objectives

### Core Objective
Build 5 long-lived supervised OTP processes (Substrate, Attention, Driver, Skeptic, Resonator) that give Lincoln continuity of process — the property that something is always running, always in some state, always doing something — whether or not anyone is talking to it.

### Concrete Deliverables
- `lib/lincoln/substrate/` — New directory containing all 5 GenServer modules + per-agent Supervisor
- `lib/lincoln/adapters/llm/ollama.ex` — Ollama LLM adapter following existing behaviour pattern
- `lib/lincoln/substrate/inference_tier.ex` — Tier selection function (local/ollama/claude)
- New migration: `belief_relationships` table with typed edges
- New migration: `attention_params` JSONB column on agents table (or `substrate_config` table)
- New PubSub topics: `:substrate`, `:attention`, `:driver`, `:skeptic`, `:resonator`
- New LiveViews: substrate dashboard, comparison view
- `mix lincoln.demo.divergence` — Demo script for two-instance divergence

### Definition of Done
- [ ] Two Lincoln instances with different attention parameters produce visibly different cognitive trajectories on the same input stream
- [ ] Lincoln runs for 24+ hours with no human input and the database has changed in non-trivial ways
- [ ] At any moment, you can query Lincoln's Substrate for what it's currently "thinking about" and get a real answer
- [ ] `mix test` passes (existing + new tests)
- [ ] Dashboard shows real-time cognitive state for all 5 processes

### Must Have
- All 5 GenServer processes running under per-agent DynamicSupervisor
- Three-tier inference (Level 0 local computation, Level 1 Ollama, Level 2 Claude)
- Parameterized attention with named parameters that produce different behavior
- Belief relationship graph for Skeptic/Resonator
- Real-time dashboard showing cognitive state
- Conversation events flowing to Substrate

### Must NOT Have (Guardrails)
- **No modification of existing Oban worker code in Steps 1-2** — new code alongside old, organic migration
- **No modification of `cognition/conversation_handler.ex` internals** — add new code path that routes to Substrate, don't rewrite the 1,448-line pipeline
- **No modification of existing belief scoring in `learning/belief_formation.ex`** — wrap and extend only
- **No umbrella app restructuring** — keep monolith
- **No clustering, distribution, or multi-node features** — single node only
- **No event sourcing** — too complex for the value. DB-derived state with periodic working-set caching
- **No replacement of `Events.Cache` GenServer** — it stays independent
- **No custom process discovery** — use Registry, not hand-rolled tracking
- **No AI-slop patterns**: no excessive comments explaining obvious code, no over-abstraction of simple operations, no generic variable names (data/result/item/temp), no premature optimization of tick loops

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES (ExUnit + Mox + DataCase)
- **Automated tests**: YES — Tests-after for new GenServer modules (test the public API contract)
- **Framework**: ExUnit with Mox for adapter mocking, DataCase for DB tests
- **GenServer testing**: Manual tick injection via `send(pid, :tick)` — no `Process.sleep` in tests

### QA Policy
Every task includes agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **GenServer processes**: Use Bash (`iex -S mix`) — start process tree, send events, query state, verify DB changes
- **LiveView dashboards**: Use Playwright — navigate to pages, verify real-time updates, screenshot state
- **Ollama adapter**: Use Bash (curl to Ollama API) — verify model availability, test inference endpoint
- **Database operations**: Use Bash (`mix test`) — run specific test files, verify migrations up/down

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Step 1 scaffolding — start immediately):
├── Task 1: DynamicSupervisor + Registry in application.ex [quick]
├── Task 2: New PubSub topics for substrate processes [quick]
└── Task 3: Substrate GenServer with tick loop [deep]

Wave 2 (Step 1 processes — after Wave 1):
├── Task 4: Attention GenServer (round-robin) [unspecified-high]
└── Task 5: Driver GenServer (basic execution) [unspecified-high]

Wave 3 (Step 1 integration — after Wave 2):
├── Task 6: Per-agent Supervisor + start/stop API [deep]
├── Task 7: Conversation event routing to Substrate [unspecified-high]
└── Task 8: Basic substrate LiveView dashboard [visual-engineering]

Wave 4 (Step 2 scaffolding — after Wave 3):
├── Task 9: Agent attention_params migration + schema [quick]
├── Task 10: Ollama LLM adapter [unspecified-high]
└── Task 11: Inference tier selection function [quick]

Wave 5 (Step 2 integration — after Wave 4):
├── Task 12: Parameterized scoring in Attention [deep]
├── Task 13: Tiered inference in Driver [unspecified-high]
└── Task 14: Attention parameter dashboard controls [visual-engineering]

Wave 6 (Step 3 scaffolding — after Wave 5):
├── Task 15: belief_relationships migration + schema [quick]
├── Task 16: Skeptic GenServer [deep]
└── Task 17: Resonator GenServer [deep]

Wave 7 (Step 3 integration — after Wave 6):
├── Task 18: Extend per-agent Supervisor to 5 processes [quick]
├── Task 19: Wire flags into Attention scoring [unspecified-high]
└── Task 20: Skeptic + Resonator dashboard panels [visual-engineering]

Wave 8 (Step 4 — after Wave 7):
├── Task 21: Multi-instance input broadcaster + trajectory recording [deep]
├── Task 22: Comparison LiveView at /substrate/compare [visual-engineering]
└── Task 23: Demo seed script (mix lincoln.demo.divergence) [unspecified-high]

Wave FINAL (after ALL tasks — 4 parallel reviews, then user okay):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
└── Task F4: Scope fidelity check (deep)
→ Present results → Get explicit user okay
```

### Dependency Matrix

| Task | Depends On | Blocks | Wave |
|------|-----------|--------|------|
| 1 | — | 3, 6 | 1 |
| 2 | — | 7, 8 | 1 |
| 3 | 1 | 4, 5, 6 | 1 |
| 4 | 3 | 6, 12 | 2 |
| 5 | 3 | 6, 13 | 2 |
| 6 | 1, 3, 4, 5 | 7, 8, 18 | 3 |
| 7 | 2, 3, 6 | — | 3 |
| 8 | 2, 6 | 14, 20, 22 | 3 |
| 9 | — | 12 | 4 |
| 10 | — | 13 | 4 |
| 11 | — | 13 | 4 |
| 12 | 4, 9 | 19 | 5 |
| 13 | 5, 10, 11 | — | 5 |
| 14 | 8, 9 | — | 5 |
| 15 | — | 16, 17 | 6 |
| 16 | 3, 15 | 18, 19 | 6 |
| 17 | 3, 15 | 18, 19 | 6 |
| 18 | 6, 16, 17 | 21 | 7 |
| 19 | 12, 16, 17 | — | 7 |
| 20 | 8, 16, 17 | — | 7 |
| 21 | 18 | 23 | 8 |
| 22 | 8, 18 | 23 | 8 |
| 23 | 21, 22 | — | 8 |

### Agent Dispatch Summary

- **Wave 1**: 3 tasks — T1 `quick`, T2 `quick`, T3 `deep`
- **Wave 2**: 2 tasks — T4 `unspecified-high`, T5 `unspecified-high`
- **Wave 3**: 3 tasks — T6 `deep`, T7 `unspecified-high`, T8 `visual-engineering`
- **Wave 4**: 3 tasks — T9 `quick`, T10 `unspecified-high`, T11 `quick`
- **Wave 5**: 3 tasks — T12 `deep`, T13 `unspecified-high`, T14 `visual-engineering`
- **Wave 6**: 3 tasks — T15 `quick`, T16 `deep`, T17 `deep`
- **Wave 7**: 3 tasks — T18 `quick`, T19 `unspecified-high`, T20 `visual-engineering`
- **Wave 8**: 3 tasks — T21 `deep`, T22 `visual-engineering`, T23 `unspecified-high`
- **FINAL**: 4 tasks — F1 `oracle`, F2 `unspecified-high`, F3 `unspecified-high`, F4 `deep`

---

## TODOs

### WAVE 1 — Step 1 Scaffolding (Start Immediately)

- [x] 1. Add DynamicSupervisor + Registry to Supervision Tree

  **What to do**:
  - Add `{DynamicSupervisor, name: Lincoln.AgentSupervisor, strategy: :one_for_one}` to the children list in `Lincoln.Application.start/2`
  - Add `{Registry, keys: :unique, name: Lincoln.AgentRegistry}` to the children list
  - Place both BEFORE Oban and AFTER PubSub in the supervision order (Registry must be available before any agent processes start)
  - Verify the application still starts cleanly with `mix phx.server`

  **Must NOT do**:
  - Modify any other children in the supervision tree
  - Remove or reorder existing children
  - Add any agent-starting logic yet — that's Task 6

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
    - Pure OTP boilerplate, no specialized knowledge needed

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3)
  - **Blocks**: Tasks 3, 6
  - **Blocked By**: None (can start immediately)

  **References**:
  - `apps/lincoln/lib/lincoln/application.ex` — Current supervision tree. Add new children here. Study the existing order: Telemetry → Repo → DNSCluster → PubSub → Oban → Events.Cache → Endpoint
  - Context7 Elixir docs: DynamicSupervisor pattern — `{DynamicSupervisor, name: MyApp.DynamicSupervisor, strategy: :one_for_one}`. Registry pattern — `{Registry, keys: :unique, name: MyApp.Registry}`
  - `apps/lincoln/test/test_helper.exs` — Existing test setup. Verify new supervision children don't break test startup

  **Acceptance Criteria**:
  - [ ] `mix phx.server` starts without errors
  - [ ] `mix test` — all existing tests still pass
  - [ ] `iex -S mix` then `DynamicSupervisor.which_children(Lincoln.AgentSupervisor)` returns `[]` (empty, no agents started yet)
  - [ ] `Registry.lookup(Lincoln.AgentRegistry, "any-key")` returns `[]`

  **QA Scenarios**:

  ```
  Scenario: Verify DynamicSupervisor and Registry are running
    Tool: Bash (iex -S mix)
    Preconditions: Application compiled and dependencies started
    Steps:
      1. Run `iex -S mix` and wait for prompt
      2. Execute `DynamicSupervisor.which_children(Lincoln.AgentSupervisor)`
      3. Execute `Registry.lookup(Lincoln.AgentRegistry, "test")`
      4. Execute `Process.whereis(Lincoln.AgentSupervisor)` — should return a PID
      5. Execute `Process.whereis(Lincoln.AgentRegistry)` — should return a PID
    Expected Result: Both return empty lists, both PIDs are non-nil
    Evidence: .sisyphus/evidence/task-1-supervisor-registry-running.txt

  Scenario: Existing tests unaffected
    Tool: Bash
    Preconditions: None
    Steps:
      1. Run `mix test`
      2. Verify exit code 0
      3. Capture test count and failure count
    Expected Result: 0 failures, same test count as before this change
    Evidence: .sisyphus/evidence/task-1-existing-tests-pass.txt
  ```

  **Commit**: YES
  - Message: `feat(substrate): add DynamicSupervisor + Registry to supervision tree`
  - Files: `apps/lincoln/lib/lincoln/application.ex`
  - Pre-commit: `mix test`

- [x] 2. Add PubSub Topics for Substrate Processes

  **What to do**:
  - Add new broadcast functions to `Lincoln.PubSub` for the 5 substrate processes:
    - `broadcast_substrate_event(agent_id, event)` — broadcasts to `agent:{id}:substrate`
    - `broadcast_attention_update(agent_id, update)` — broadcasts to `agent:{id}:attention`
    - `broadcast_driver_action(agent_id, action)` — broadcasts to `agent:{id}:driver`
    - `broadcast_skeptic_flag(agent_id, flag)` — broadcasts to `agent:{id}:skeptic`
    - `broadcast_resonator_flag(agent_id, flag)` — broadcasts to `agent:{id}:resonator`
  - Add corresponding topic helper functions: `substrate_topic(agent_id)`, `attention_topic(agent_id)`, etc.
  - Follow the exact pattern of existing `broadcast_belief_created/2`, `broadcast_question_created/2`, etc.

  **Must NOT do**:
  - Modify existing broadcast functions
  - Change existing topic naming convention
  - Add any subscribers yet — LiveViews subscribe in Task 8

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
    - Following existing pattern exactly, no complexity

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3)
  - **Blocks**: Tasks 7, 8
  - **Blocked By**: None

  **References**:
  - `apps/lincoln/lib/lincoln/pub_sub.ex:1-111` — **THE pattern to follow exactly**. Study existing broadcast functions (broadcast_belief_created, broadcast_question_created, etc.) and topic helpers. New functions must match this style precisely.
  - `apps/lincoln/lib/lincoln/events/emitter.ex:1-88` — Event emission pattern, complementary to PubSub

  **Acceptance Criteria**:
  - [ ] `Lincoln.PubSub.substrate_topic("agent-123")` returns `"agent:agent-123:substrate"`
  - [ ] All 5 new topic helpers and 5 new broadcast functions exist
  - [ ] `mix test` passes (existing tests unaffected)
  - [ ] New functions follow identical pattern to existing ones

  **QA Scenarios**:

  ```
  Scenario: PubSub topics follow naming convention
    Tool: Bash (iex -S mix)
    Preconditions: Application compiled
    Steps:
      1. Run `iex -S mix`
      2. Execute `Lincoln.PubSub.substrate_topic("test-agent")`
      3. Execute `Lincoln.PubSub.attention_topic("test-agent")`
      4. Execute `Lincoln.PubSub.driver_topic("test-agent")`
      5. Execute `Lincoln.PubSub.skeptic_topic("test-agent")`
      6. Execute `Lincoln.PubSub.resonator_topic("test-agent")`
    Expected Result: Returns "agent:test-agent:substrate", "agent:test-agent:attention", etc.
    Evidence: .sisyphus/evidence/task-2-pubsub-topics.txt

  Scenario: Broadcast functions work
    Tool: Bash (iex -S mix)
    Preconditions: Application started
    Steps:
      1. Subscribe to substrate topic: `Phoenix.PubSub.subscribe(Lincoln.PubSub, Lincoln.PubSub.substrate_topic("test"))`
      2. Broadcast: `Lincoln.PubSub.broadcast_substrate_event("test", %{type: :tick, data: "hello"})`
      3. Check mailbox: `flush()` — should show the broadcast message
    Expected Result: Message received matching broadcast payload
    Evidence: .sisyphus/evidence/task-2-pubsub-broadcast.txt
  ```

  **Commit**: YES
  - Message: `feat(substrate): add PubSub topics for substrate processes`
  - Files: `apps/lincoln/lib/lincoln/pub_sub.ex`
  - Pre-commit: `mix test`

- [x] 3. Substrate GenServer with Tick Loop and Cognitive State

  **What to do**:
  - Create `lib/lincoln/substrate/substrate.ex` — the core GenServer
  - State struct holds: `agent_id`, `current_focus` (what's being thought about), `activation_map` (recently activated belief regions), `pending_events` (queue of unprocessed external events), `tick_count`, `last_tick_at`
  - `init/1`: Takes `agent_id`, loads agent from DB, reconstructs working state from recent beliefs/memories, schedules first tick
  - `handle_info(:tick, state)`: The core loop — process one pending event OR advance current focus. Broadcast state via PubSub. Schedule next tick.
  - `handle_cast({:event, event}, state)`: External events (conversations, observations) enqueued into `pending_events`
  - `handle_call(:get_state, _, state)`: Returns current cognitive state (for dashboard and testing)
  - Tick interval configurable via agent params, default 5000ms
  - Use `Process.send_after(self(), :tick, interval)` pattern from Context7 docs
  - Register via `{:via, Registry, {Lincoln.AgentRegistry, {agent_id, :substrate}}}`
  - Implement `child_spec/1` with explicit `:id` for Registry uniqueness
  - **For Step 1, the tick does minimal work**: process one pending event (just acknowledge and log it), or if no events, pick the least-recently-updated belief and mark it as "current focus"

  **Must NOT do**:
  - Call any LLM (that's the Driver's job, later)
  - Implement scoring (that's the Attention's job)
  - Modify beliefs or memories (that's Step 2+)
  - Use `Process.sleep` anywhere

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - Core architectural component requiring careful OTP design. State management, crash recovery, message protocol design.

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2) — BUT uses DynamicSupervisor from Task 1 in integration
  - **Blocks**: Tasks 4, 5, 6
  - **Blocked By**: Task 1 (for Registry name)

  **References**:
  - `apps/lincoln/lib/lincoln/workers/autonomous_learning_worker.ex:1-680` — **THE proto-Substrate**. Study its cycle scheduling (line ~55-73), budget checking, session lifecycle. The GenServer replaces this pattern with persistent in-memory state instead of DB reconstruction each cycle.
  - `apps/lincoln/lib/lincoln/events/cache.ex` — **Only existing GenServer**. Study its `init/1`, `handle_info` for cleanup ticks, ETS usage. Follow the same OTP patterns.
  - `apps/lincoln/lib/lincoln/beliefs.ex` — Beliefs context module. Use `list_beliefs/2` to load recent beliefs for state reconstruction in `init/1`.
  - `apps/lincoln/lib/lincoln/memory.ex` — Memory context. Use `list_recent_memories/2` for state reconstruction.
  - Context7 Elixir docs: GenServer tick pattern — `Process.send_after(self(), :work, interval)` in `init` and `handle_info`.
  - Context7 Elixir docs: Registry naming — `{:via, Registry, {MyApp.Registry, key}}` for GenServer.start_link name option.

  **Acceptance Criteria**:
  - [ ] Module compiles: `mix compile --warnings-as-errors`
  - [ ] Unit test: `send(pid, :tick)` advances `tick_count` by 1
  - [ ] Unit test: `GenServer.cast(pid, {:event, %{type: :test}})` adds to `pending_events`
  - [ ] Unit test: `GenServer.call(pid, :get_state)` returns state struct with all expected fields
  - [ ] Integration: Process registers in `Lincoln.AgentRegistry` under `{agent_id, :substrate}`

  **QA Scenarios**:

  ```
  Scenario: Substrate ticks and processes events
    Tool: Bash (iex -S mix)
    Preconditions: Application started, at least one agent in DB
    Steps:
      1. Start a substrate process: `{:ok, pid} = Lincoln.Substrate.Substrate.start_link(%{agent_id: agent_id})`
      2. Send an event: `GenServer.cast(pid, {:event, %{type: :test, content: "hello"}})`
      3. Trigger a tick: `send(pid, :tick)`
      4. Query state: `{:ok, state} = GenServer.call(pid, :get_state)`
      5. Verify `state.tick_count == 1`
      6. Verify `state.pending_events` is empty (event was processed)
    Expected Result: tick_count incremented, pending_events drained
    Evidence: .sisyphus/evidence/task-3-substrate-tick.txt

  Scenario: Substrate registers in Registry
    Tool: Bash (iex -S mix)
    Preconditions: Application started, agent exists
    Steps:
      1. Start substrate with agent_id "test-agent"
      2. Execute `Registry.lookup(Lincoln.AgentRegistry, {"test-agent", :substrate})`
      3. Verify returns `[{pid, nil}]` where pid matches the started process
    Expected Result: Process found in Registry under expected key
    Evidence: .sisyphus/evidence/task-3-substrate-registry.txt

  Scenario: Substrate recovers state from DB on init
    Tool: Bash (iex -S mix)
    Preconditions: Agent with existing beliefs in DB
    Steps:
      1. Start substrate for agent that has beliefs
      2. Query state immediately after start
      3. Verify `state.current_focus` is not nil (loaded from recent beliefs)
    Expected Result: State initialized from DB, not empty
    Evidence: .sisyphus/evidence/task-3-substrate-init-recovery.txt
  ```

  **Commit**: YES
  - Message: `feat(substrate): add Substrate GenServer with tick loop and cognitive state`
  - Files: `apps/lincoln/lib/lincoln/substrate/substrate.ex`, `apps/lincoln/test/lincoln/substrate/substrate_test.exs`
  - Pre-commit: `mix test`

---

### WAVE 2 — Step 1 Processes (After Wave 1)

- [x] 4. Attention GenServer — Round-Robin Over Beliefs

  **What to do**:
  - Create `lib/lincoln/substrate/attention.ex` — GenServer that decides "what to think about next"
  - State: `agent_id`, `belief_cursor` (position in iteration), `current_candidates` (list of scored beliefs), `last_scored_at`
  - `handle_call(:next_thought, _, state)`: Returns the next belief to focus on. For Step 1, this is simply round-robin by `updated_at` — pick the least-recently-updated active belief.
  - `handle_cast({:notify, event}, state)`: Receives notifications from Substrate about new events. In Step 1, ignores them (scoring comes in Step 2).
  - Register via `{:via, Registry, {Lincoln.AgentRegistry, {agent_id, :attention}}}`
  - NO tick loop in Attention — it's reactive (called by Substrate/Driver), not proactive
  - Query beliefs via `Lincoln.Beliefs.list_beliefs/2` with ordering by `updated_at ASC`

  **Must NOT do**:
  - Implement scoring (that's Step 2, Task 12)
  - Call any LLM
  - Modify beliefs
  - Use novelty_weight, focus_momentum, etc. parameters (Step 2)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 5)
  - **Blocks**: Tasks 6, 12
  - **Blocked By**: Task 3 (needs Substrate pattern established)

  **References**:
  - `apps/lincoln/lib/lincoln/beliefs.ex` — `list_beliefs/2` for querying beliefs. Study the available query options and filters.
  - `apps/lincoln/lib/lincoln/learning/belief_formation.ex:375-393` — **Existing attention-like scoring**. DO NOT use in Step 1 (round-robin only), but study for Step 2. Contains: `learning_priority`, `revision_urgency`, `metacognitive_flags`, `decision_weight`.
  - `apps/lincoln/lib/lincoln/substrate/substrate.ex` (from Task 3) — Follow same OTP patterns (child_spec, Registry naming, state struct)

  **Acceptance Criteria**:
  - [ ] `GenServer.call(pid, :next_thought)` returns `{:ok, %Lincoln.Beliefs.Belief{}}` — the least-recently-updated belief
  - [ ] Calling `:next_thought` twice returns different beliefs (advances cursor)
  - [ ] Returns `{:ok, nil}` when agent has no beliefs
  - [ ] Registers in Registry under `{agent_id, :attention}`

  **QA Scenarios**:

  ```
  Scenario: Round-robin returns beliefs in least-recently-updated order
    Tool: Bash (mix test)
    Preconditions: Test DB with agent having 3+ beliefs with different updated_at timestamps
    Steps:
      1. Start Attention GenServer for test agent
      2. Call :next_thought — should return oldest belief
      3. Call :next_thought again — should return next oldest
      4. Call :next_thought again — should return next
    Expected Result: Beliefs returned in ascending updated_at order
    Evidence: .sisyphus/evidence/task-4-attention-round-robin.txt

  Scenario: Attention handles agent with no beliefs
    Tool: Bash (mix test)
    Preconditions: Test agent with 0 beliefs
    Steps:
      1. Start Attention GenServer
      2. Call :next_thought
    Expected Result: Returns {:ok, nil}
    Evidence: .sisyphus/evidence/task-4-attention-no-beliefs.txt
  ```

  **Commit**: YES
  - Message: `feat(substrate): add Attention GenServer with round-robin belief iteration`
  - Files: `apps/lincoln/lib/lincoln/substrate/attention.ex`, `apps/lincoln/test/lincoln/substrate/attention_test.exs`
  - Pre-commit: `mix test`

- [x] 5. Driver GenServer — Basic Event Execution

  **What to do**:
  - Create `lib/lincoln/substrate/driver.ex` — GenServer that executes whatever Attention decided
  - State: `agent_id`, `current_action` (what's being executed), `last_completed_action`, `action_history` (ring buffer of last N actions)
  - `handle_cast({:execute, thought}, state)`: Takes a thought from Attention and "executes" it. For Step 1, execution is minimal: log the thought to the events table via `Lincoln.Events.Cache`, broadcast via PubSub, update `current_action`.
  - `handle_cast({:execute_event, event}, state)`: Process an external event (from conversation). For Step 1: log it, broadcast it.
  - No LLM calls in Step 1. No Ollama. Just logging and state tracking.
  - Register via `{:via, Registry, {Lincoln.AgentRegistry, {agent_id, :driver}}}`
  - When execution completes, send `:execution_complete` message back to Substrate (so Substrate knows to advance to next tick)

  **Must NOT do**:
  - Call any LLM (Level 1 or Level 2) — that's Step 2
  - Modify beliefs or memories — that's Step 2+
  - Implement inference tier selection — that's Task 11
  - Block on anything — execution is fire-and-forget in Step 1

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Task 4)
  - **Blocks**: Tasks 6, 13
  - **Blocked By**: Task 3

  **References**:
  - `apps/lincoln/lib/lincoln/events/cache.ex` — ETS-backed event caching. Use `Lincoln.Events.Cache.record_event/3` to log actions.
  - `apps/lincoln/lib/lincoln/pub_sub.ex` — Use `broadcast_driver_action/2` (from Task 2) to broadcast execution.
  - `apps/lincoln/lib/lincoln/substrate/substrate.ex` (from Task 3) — Follow same OTP patterns. Driver sends `:execution_complete` back to Substrate.

  **Acceptance Criteria**:
  - [ ] `GenServer.cast(pid, {:execute, belief})` logs event to Events.Cache
  - [ ] After execution, Substrate receives `:execution_complete` message
  - [ ] `GenServer.call(pid, :get_state)` returns current/last action
  - [ ] PubSub broadcast fires on execution

  **QA Scenarios**:

  ```
  Scenario: Driver executes a thought and notifies Substrate
    Tool: Bash (mix test)
    Preconditions: Substrate and Driver processes started for same agent
    Steps:
      1. Subscribe to driver PubSub topic
      2. Cast {:execute, %{type: :belief_reflection, belief_id: "test-123"}} to Driver
      3. Verify PubSub message received with action details
      4. Query Driver state — current_action should reflect execution
      5. Verify Substrate received :execution_complete
    Expected Result: Event logged, PubSub broadcast sent, Substrate notified
    Evidence: .sisyphus/evidence/task-5-driver-execute.txt
  ```

  **Commit**: YES
  - Message: `feat(substrate): add Driver GenServer with basic event execution`
  - Files: `apps/lincoln/lib/lincoln/substrate/driver.ex`, `apps/lincoln/test/lincoln/substrate/driver_test.exs`
  - Pre-commit: `mix test`

---

### WAVE 3 — Step 1 Integration (After Wave 2)

- [x] 6. Per-Agent Supervisor + Start/Stop API

  **What to do**:
  - Create `lib/lincoln/substrate/agent_supervisor.ex` — Supervisor module that starts all processes for one agent
  - `start_link(agent_id)`: Starts a Supervisor with children [Substrate, Attention, Driver] — each receiving `%{agent_id: agent_id}`
  - Strategy: `:one_for_all` — if any process crashes, restart all (they depend on shared state assumptions)
  - Create `lib/lincoln/substrate.ex` — Public API module:
    - `start_agent(agent_id)` — calls `DynamicSupervisor.start_child(Lincoln.AgentSupervisor, {AgentSupervisor, agent_id})`
    - `stop_agent(agent_id)` — finds and terminates the agent's supervisor
    - `get_agent_state(agent_id)` — looks up Substrate via Registry, calls `:get_state`
    - `send_event(agent_id, event)` — looks up Substrate via Registry, casts `{:event, event}`
    - `list_running_agents()` — queries DynamicSupervisor.which_children
  - Validate agent exists in DB before starting processes

  **Must NOT do**:
  - Auto-start agents on application boot (manual start for now)
  - Add Skeptic or Resonator to children (that's Step 3, Task 18)
  - Implement any restart-on-deploy logic

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - OTP supervision design, process lifecycle, Registry integration — requires careful architecture

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 8)
  - **Blocks**: Tasks 7, 8, 18
  - **Blocked By**: Tasks 1, 3, 4, 5

  **References**:
  - `apps/lincoln/lib/lincoln/application.ex` — Study existing supervision tree to understand how AgentSupervisor fits
  - Context7 Elixir docs: DynamicSupervisor.start_child pattern, Registry `{:via, ...}` tuple for naming
  - `apps/lincoln/lib/lincoln/agents.ex` — `get_agent!/1` to validate agent exists before starting processes
  - `apps/lincoln/lib/lincoln/substrate/substrate.ex`, `attention.ex`, `driver.ex` (from Tasks 3-5) — These are the children to supervise

  **Acceptance Criteria**:
  - [ ] `Lincoln.Substrate.start_agent(agent_id)` starts 3 processes (Substrate, Attention, Driver)
  - [ ] All 3 processes registered in Registry under `{agent_id, :substrate}`, `{agent_id, :attention}`, `{agent_id, :driver}`
  - [ ] `Lincoln.Substrate.stop_agent(agent_id)` terminates all 3 processes
  - [ ] `Lincoln.Substrate.get_agent_state(agent_id)` returns current cognitive state
  - [ ] `Lincoln.Substrate.send_event(agent_id, event)` delivers event to Substrate process
  - [ ] Starting an agent that doesn't exist in DB returns `{:error, :agent_not_found}`
  - [ ] Starting an already-running agent returns `{:error, :already_started}`

  **QA Scenarios**:

  ```
  Scenario: Full agent lifecycle — start, interact, stop
    Tool: Bash (iex -S mix)
    Preconditions: At least one agent in database
    Steps:
      1. Start agent: `{:ok, pid} = Lincoln.Substrate.start_agent(agent_id)`
      2. List running: `Lincoln.Substrate.list_running_agents()` — should include agent_id
      3. Send event: `Lincoln.Substrate.send_event(agent_id, %{type: :test, content: "hello"})`
      4. Wait 2 ticks (10 seconds with default 5s interval)
      5. Get state: `{:ok, state} = Lincoln.Substrate.get_agent_state(agent_id)`
      6. Verify state.tick_count >= 2 and pending_events is empty
      7. Stop: `Lincoln.Substrate.stop_agent(agent_id)`
      8. List running: should no longer include agent_id
    Expected Result: Full lifecycle works — start, interact, query, stop
    Evidence: .sisyphus/evidence/task-6-agent-lifecycle.txt

  Scenario: Error handling for invalid agent
    Tool: Bash (iex -S mix)
    Preconditions: No agent with id "nonexistent" in DB
    Steps:
      1. `Lincoln.Substrate.start_agent("nonexistent")`
    Expected Result: Returns {:error, :agent_not_found}
    Evidence: .sisyphus/evidence/task-6-invalid-agent.txt
  ```

  **Commit**: YES
  - Message: `feat(substrate): add per-agent Supervisor and public start/stop API`
  - Files: `apps/lincoln/lib/lincoln/substrate/agent_supervisor.ex`, `apps/lincoln/lib/lincoln/substrate.ex`, `apps/lincoln/test/lincoln/substrate_test.exs`
  - Pre-commit: `mix test`

- [x] 7. Conversation Event Routing to Substrate

  **What to do**:
  - Add a NEW code path in the conversation flow that sends events to the Substrate process — WITHOUT modifying the existing `ConversationHandler` internals
  - Create `lib/lincoln/substrate/conversation_bridge.ex` — a module that:
    - Takes a processed message (after ConversationHandler finishes) and wraps it as a Substrate event
    - Checks if the agent has a running Substrate process (via Registry lookup)
    - If yes: `GenServer.cast(substrate_pid, {:event, %{type: :conversation, content: message, metadata: cognitive_metadata}})`
    - If no: silently skip (Substrate isn't required for chat to work)
    - The cognitive metadata from ConversationHandler (memories retrieved, beliefs consulted, contradictions detected) becomes part of the event
  - Call `ConversationBridge.notify/3` from the CALLER of ConversationHandler, not from inside it
  - Find the call site in the LiveView or controller that invokes `ConversationHandler.process_message/3` and add the bridge call after it returns

  **Must NOT do**:
  - Modify `cognition/conversation_handler.ex` — zero changes to the 1,448-line file
  - Make Substrate a dependency of conversation — chat must work whether or not Substrate is running
  - Block the conversation response on Substrate processing
  - Change the existing chat UX in any way

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 6, 8)
  - **Blocks**: None
  - **Blocked By**: Tasks 2, 3, 6

  **References**:
  - `apps/lincoln/lib/lincoln/cognition/conversation_handler.ex` — **DO NOT MODIFY**. Read to understand what cognitive metadata is available after `process_message/3` returns (memories_retrieved, beliefs_consulted, beliefs_revised, contradictions_detected, thinking_summary).
  - `apps/lincoln/lib/lincoln_web/live/chat_live.ex` — Find where `process_message/3` is called. Add `ConversationBridge.notify/3` call AFTER it.
  - `apps/lincoln/lib/lincoln/substrate.ex` (from Task 6) — Use `send_event/2` public API, not direct GenServer calls

  **Acceptance Criteria**:
  - [ ] Chat conversation works identically with or without Substrate running
  - [ ] When Substrate IS running: each chat message creates a `:conversation` event in Substrate's pending_events
  - [ ] Substrate event includes cognitive metadata from the conversation
  - [ ] No changes to `conversation_handler.ex` (verify via `git diff`)
  - [ ] `mix test` passes — existing conversation tests unaffected

  **QA Scenarios**:

  ```
  Scenario: Chat message flows to Substrate
    Tool: Bash (iex -S mix)
    Preconditions: Agent running with Substrate process active
    Steps:
      1. Start agent substrate: `Lincoln.Substrate.start_agent(agent_id)`
      2. Send a chat message through the normal conversation path
      3. Query substrate state: `Lincoln.Substrate.get_agent_state(agent_id)`
      4. Verify pending_events contains a :conversation type event
    Expected Result: Conversation event appears in Substrate
    Evidence: .sisyphus/evidence/task-7-conversation-bridge.txt

  Scenario: Chat works without Substrate
    Tool: Bash (iex -S mix)
    Preconditions: Agent exists but NO Substrate process running
    Steps:
      1. Ensure no substrate is running for this agent
      2. Send a chat message through normal path
      3. Verify response comes back normally, no errors
    Expected Result: Chat is unaffected — bridge silently skips
    Evidence: .sisyphus/evidence/task-7-chat-without-substrate.txt
  ```

  **Commit**: YES
  - Message: `feat(substrate): add conversation bridge to route chat events to Substrate`
  - Files: `apps/lincoln/lib/lincoln/substrate/conversation_bridge.ex`, call site in `chat_live.ex` or controller
  - Pre-commit: `mix test`

- [x] 8. Basic Substrate LiveView Dashboard

  **What to do**:
  - Create `lib/lincoln_web/live/substrate_live.ex` — new LiveView page at `/substrate`
  - Subscribe to PubSub topics for the active agent: `:substrate`, `:attention`, `:driver`
  - Display:
    - **Substrate state**: current focus, tick count, pending events count, last tick time
    - **Attention**: last scored candidates (empty in Step 1, placeholder for Step 2)
    - **Driver**: current action, last completed action, action history
    - **Event timeline**: scrolling list of recent events processed by the substrate
  - Add route to router: `live "/substrate", SubstrateLive`
  - Follow existing dashboard design patterns from `dashboard_live.ex` — daisyUI cards, stat grids, dark theme
  - Add navigation link to existing sidebar/nav

  **Must NOT do**:
  - Show Skeptic or Resonator panels (they don't exist yet — Task 20)
  - Build the comparison view (that's Task 22)
  - Modify existing LiveView pages

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 6, 7)
  - **Blocks**: Tasks 14, 20, 22
  - **Blocked By**: Tasks 2, 6

  **References**:
  - `apps/lincoln/lib/lincoln_web/live/dashboard_live.ex` — **Follow this pattern exactly** for layout, styling, PubSub subscription, handle_info. Study: mount/3, how it subscribes to PubSub, how it loads initial data, how handle_info updates assigns.
  - `apps/lincoln/lib/lincoln_web/live/chat_live.ex` — Study the worker sidebar pattern for the event timeline component
  - `apps/lincoln/lib/lincoln_web/router.ex` — Add new route following existing pattern
  - `apps/lincoln/lib/lincoln/pub_sub.ex` — Topic functions from Task 2 for subscribing
  - `apps/lincoln/assets/css/app.css` — Custom neural aesthetic utilities and daisyUI theme

  **Acceptance Criteria**:
  - [ ] `/substrate` route loads without error
  - [ ] When agent substrate is running, dashboard shows live tick count updating in real-time
  - [ ] Event timeline shows events as they're processed
  - [ ] When no agent is running, shows "No active substrate" message
  - [ ] Matches existing dashboard visual style (daisyUI, dark theme)

  **QA Scenarios**:

  ```
  Scenario: Dashboard shows live substrate state
    Tool: Playwright (playwright skill)
    Preconditions: Phoenix server running, agent substrate started
    Steps:
      1. Navigate to http://localhost:4000/substrate
      2. Wait for page load (selector: "[data-role='substrate-dashboard']")
      3. Verify tick count element exists and shows a number
      4. Wait 10 seconds
      5. Verify tick count has increased
      6. Take screenshot
    Expected Result: Dashboard loads, shows live updating tick count
    Evidence: .sisyphus/evidence/task-8-dashboard-live.png

  Scenario: Dashboard handles no active substrate
    Tool: Playwright
    Preconditions: Phoenix server running, NO substrate started
    Steps:
      1. Navigate to http://localhost:4000/substrate
      2. Verify "No active substrate" message is visible
    Expected Result: Graceful empty state
    Evidence: .sisyphus/evidence/task-8-dashboard-empty.png
  ```

  **Commit**: YES
  - Message: `feat(substrate): add substrate LiveView dashboard at /substrate`
  - Files: `apps/lincoln/lib/lincoln_web/live/substrate_live.ex`, `apps/lincoln/lib/lincoln_web/router.ex`
  - Pre-commit: `mix test`

---

### WAVE 4 — Step 2 Scaffolding (After Wave 3)

- [x] 9. Agent Attention Parameters Migration + Schema

  **What to do**:
  - Create migration: add `attention_params` column to `agents` table — type `:map` (JSONB)
  - Default value: `%{novelty_weight: 0.3, focus_momentum: 0.5, interrupt_threshold: 0.7, boredom_decay: 0.1, depth_preference: 0.5, tick_interval_ms: 5000}`
  - Update `Lincoln.Agents.Agent` schema to include `field :attention_params, :map, default: %{}`
  - Add changeset validation: all param values must be floats between 0.0 and 1.0 (except `tick_interval_ms` which is integer 1000-60000)
  - Preset configurations as module constants:
    - `@focused`: high focus_momentum (0.8), low boredom_decay (0.05), high depth_preference (0.8)
    - `@butterfly`: low focus_momentum (0.2), high novelty_weight (0.8), high boredom_decay (0.3)
    - `@adhd_like`: high focus_momentum when engaged (0.9), low baseline (0.1), very high interrupt_threshold (0.9), high boredom_decay (0.4)
  - Create `lib/lincoln/substrate/attention_params.ex` — struct + validation + presets

  **Must NOT do**:
  - Modify existing agent fields
  - Make attention_params required (nullable with defaults)
  - Externalize the hardcoded constants from `belief_formation.ex` yet — that's an enhancement, not this task

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 10, 11)
  - **Blocks**: Tasks 12, 14
  - **Blocked By**: None (pure schema work)

  **References**:
  - `apps/lincoln/lib/lincoln/agents/agent.ex` — Current agent schema. Add `field :attention_params, :map` here. Study existing changeset for validation patterns.
  - `apps/lincoln/priv/repo/migrations/` — Follow existing migration naming pattern (timestamp prefix)
  - Architecture sketch "The Attention" section — parameter names: novelty vs depth weight, interrupt threshold, momentum, boredom decay

  **Acceptance Criteria**:
  - [ ] Migration runs cleanly: `mix ecto.migrate`
  - [ ] Migration rolls back cleanly: `mix ecto.rollback --step 1`
  - [ ] `AttentionParams.focused()` returns preset map
  - [ ] `AttentionParams.validate(%{novelty_weight: 1.5})` returns error (out of range)
  - [ ] Existing agent tests pass

  **QA Scenarios**:

  ```
  Scenario: Migration up and down
    Tool: Bash
    Preconditions: Database exists
    Steps:
      1. Run `mix ecto.migrate`
      2. Verify agents table has attention_params column: query via iex
      3. Run `mix ecto.rollback --step 1`
      4. Verify column is gone
      5. Run `mix ecto.migrate` again
    Expected Result: Clean migrate, rollback, re-migrate
    Evidence: .sisyphus/evidence/task-9-migration.txt
  ```

  **Commit**: YES
  - Message: `feat(attention): add attention_params to agent schema with presets`
  - Files: migration file, `agents/agent.ex`, `substrate/attention_params.ex`, test file
  - Pre-commit: `mix test`

- [x] 10. Ollama LLM Adapter

  **What to do**:
  - Create `lib/lincoln/adapters/llm/ollama.ex` — implements `Lincoln.Adapters.LLM` behaviour
  - Implement all 3 callbacks following existing Anthropic adapter pattern:
    - `chat(messages, opts)` — POST to `http://localhost:11434/api/chat` with model, messages, `stream: false`
    - `complete(prompt, opts)` — Wraps prompt as user message, calls chat
    - `extract(prompt, schema, opts)` — Calls chat with JSON instruction in system message, parses response
  - Use `Req` library (already a dependency) for HTTP calls
  - Default model: configurable via `config :lincoln, :ollama, model: "qwen2.5:7b"` — but overridable per call via `opts[:model]`
  - Add health check: `health_check()` — GET `http://localhost:11434/api/tags`, returns `:ok` or `{:error, reason}`
  - Create `lib/lincoln/adapters/llm/ollama_mock.ex` for testing (or extend existing Mox setup)
  - Add Ollama service to `docker-compose.yml` (GPU passthrough if available, CPU fallback)
  - Handle Ollama not running gracefully: return `{:error, :ollama_unavailable}`, not crash

  **Must NOT do**:
  - Modify the existing Anthropic adapter
  - Change the `Lincoln.Adapters.LLM` behaviour interface
  - Make Ollama a hard dependency — system must work without it (falls back to Claude-only)
  - Implement streaming (not needed for background cognition ticks)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 9, 11)
  - **Blocks**: Task 13
  - **Blocked By**: None

  **References**:
  - `apps/lincoln/lib/lincoln/adapters/llm.ex:1-189` — **THE behaviour to implement**. Study the callback specs: `chat/2`, `complete/2`, `extract/3`. Study the Anthropic implementation for HTTP call patterns, error handling, response parsing.
  - `apps/lincoln/config/config.exs` — See how `:llm` config is structured. Add parallel `:ollama` config.
  - `apps/lincoln/config/test.exs` — See how Mox mock is configured for tests
  - `apps/lincoln/test/test_helper.exs` — Mox.defmock setup. Add Ollama mock here.
  - Context7 Ollama docs: `POST /api/chat` — `{model, messages, stream: false}` → `{message: {role, content}, done, eval_count, eval_duration}`
  - Context7 Ollama docs: `GET /api/tags` — lists available models for health check
  - `docker-compose.yml` — Add Ollama service alongside existing postgres and ml_service

  **Acceptance Criteria**:
  - [ ] `Lincoln.Adapters.LLM.Ollama.health_check()` returns `:ok` when Ollama is running
  - [ ] `Lincoln.Adapters.LLM.Ollama.chat([%{role: "user", content: "ping"}], [])` returns `{:ok, %{content: _}}`
  - [ ] Returns `{:error, :ollama_unavailable}` when Ollama is not running
  - [ ] Mox mock works in test suite
  - [ ] Existing tests unaffected

  **QA Scenarios**:

  ```
  Scenario: Ollama adapter chat works (integration)
    Tool: Bash
    Preconditions: Ollama running with qwen2.5:7b pulled
    Steps:
      1. Run in iex: `Lincoln.Adapters.LLM.Ollama.chat([%{role: "user", content: "Say hello in one word"}], model: "qwen2.5:0.5b")`
      2. Verify returns {:ok, %{content: content}} where content is a non-empty string
    Expected Result: Successful response from local model
    Evidence: .sisyphus/evidence/task-10-ollama-chat.txt

  Scenario: Ollama unavailable handled gracefully
    Tool: Bash
    Preconditions: Ollama NOT running
    Steps:
      1. Run in iex: `Lincoln.Adapters.LLM.Ollama.health_check()`
      2. Verify returns {:error, :ollama_unavailable}
      3. Run: `Lincoln.Adapters.LLM.Ollama.chat([%{role: "user", content: "test"}], [])`
      4. Verify returns {:error, :ollama_unavailable} — no crash
    Expected Result: Graceful error handling, no crashes
    Evidence: .sisyphus/evidence/task-10-ollama-unavailable.txt
  ```

  **Commit**: YES
  - Message: `feat(attention): add Ollama LLM adapter for local inference`
  - Files: `adapters/llm/ollama.ex`, test file, `docker-compose.yml`, `config/config.exs`
  - Pre-commit: `mix test`

- [x] 11. Inference Tier Selection Function

  **What to do**:
  - Create `lib/lincoln/substrate/inference_tier.ex` — pure function module, no GenServer
  - `select_tier(attention_score, opts)` returns `:local | :ollama | :claude`
    - `:local` (Level 0) — attention_score < 0.3. No model call. Pure computation.
    - `:ollama` (Level 1) — attention_score >= 0.3 and < 0.7. Local model for reflection/question generation.
    - `:claude` (Level 2) — attention_score >= 0.7. Frontier model for deep reasoning.
  - Thresholds configurable via `opts` or agent's attention_params
  - `execute_at_tier(tier, action, opts)` — dispatches to appropriate adapter:
    - `:local` → returns `{:ok, :skipped}` (caller handles locally)
    - `:ollama` → calls `Lincoln.Adapters.LLM.Ollama.chat/2`
    - `:claude` → calls configured LLM adapter (Anthropic)
  - Fallback logic: if `:ollama` fails → try `:claude`. If `:claude` fails → return error.
  - Include token budget check: if budget is `:minimal`, force `:local` regardless of score

  **Must NOT do**:
  - Build complex routing chains
  - Add caching or queuing
  - Make this a GenServer — it's a pure function module

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []
    - Pure function, well-defined inputs/outputs, exhaustive testing

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 9, 10)
  - **Blocks**: Task 13
  - **Blocked By**: None (pure logic, adapters are injected)

  **References**:
  - `apps/lincoln/lib/lincoln/autonomy/token_budget.ex` — Existing budget system. Use `suggest_operations/1` to get budget tier (`:full`, `:moderate`, `:conservative`, `:minimal`). When `:minimal`, force Level 0.
  - `apps/lincoln/lib/lincoln/adapters/llm.ex` — LLM behaviour for dispatching calls
  - Architecture sketch "Tiering" section — "Most ticks should do cheap operations... Only escalate to a frontier model when the attention process scores a candidate above some threshold"

  **Acceptance Criteria**:
  - [ ] `select_tier(0.1, [])` returns `:local`
  - [ ] `select_tier(0.5, [])` returns `:ollama`
  - [ ] `select_tier(0.9, [])` returns `:claude`
  - [ ] `select_tier(0.9, budget: :minimal)` returns `:local` (budget override)
  - [ ] Thresholds are configurable via opts
  - [ ] 100% of branches covered in tests

  **QA Scenarios**:

  ```
  Scenario: Tier selection covers all ranges
    Tool: Bash (mix test)
    Preconditions: None (pure function)
    Steps:
      1. Run test file with property-based edge cases
      2. Test boundary values: 0.0, 0.29, 0.3, 0.69, 0.7, 1.0
      3. Test budget override at each tier
    Expected Result: All assertions pass, every branch exercised
    Evidence: .sisyphus/evidence/task-11-tier-selection.txt
  ```

  **Commit**: YES
  - Message: `feat(attention): add inference tier selection function`
  - Files: `substrate/inference_tier.ex`, test file
  - Pre-commit: `mix test`

---

### WAVE 5 — Step 2 Integration (After Wave 4)

- [x] 12. Parameterized Scoring in Attention GenServer

  **What to do**:
  - Replace the round-robin logic in `Attention` (from Task 4) with a scoring function
  - Load agent's `attention_params` on init
  - `score_belief(belief, state, params)` returns a float 0.0-1.0:
    - `recency_score` = time since `last_reinforced_at` or `updated_at` (older = lower score, but NOT zero — old beliefs deserve occasional revisiting)
    - `tension_score` = high confidence + recent challenge (`last_challenged_at` within N hours) = high tension. Or: low confidence + high entrenchment = tension.
    - `novelty_score` = recently created beliefs, or beliefs with few revisions
    - `staleness_score` = time since last "focused on" (tracked in Substrate's activation_map)
    - Combined: `params.novelty_weight * novelty + params.depth_preference * tension + (1 - params.boredom_decay) * staleness + params.focus_momentum * current_focus_bonus`
  - Build on existing formulas from `learning/belief_formation.ex:375-393` — don't reinvent `learning_priority` and `revision_urgency`, wrap them
  - `handle_call(:next_thought, _, state)` now returns the highest-scored belief, along with the attention_score (for tier selection in Driver)
  - The attention_score also determines inference tier: score < 0.3 = local, 0.3-0.7 = ollama, > 0.7 = claude
  - Different `attention_params` presets must produce measurably different belief orderings — this is THE test of Property 4

  **Must NOT do**:
  - Modify `learning/belief_formation.ex` — import and use its functions
  - Make the scoring function opaque — it must be inspectable for the dashboard
  - Add any ML/embedding-based scoring yet (embeddings are for Resonator, Step 3)

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - Mathematical scoring function, parameter sensitivity, property-based testing

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 13, 14)
  - **Blocks**: Task 19
  - **Blocked By**: Tasks 4, 9

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/attention.ex` (from Task 4) — Replace round-robin with scoring
  - `apps/lincoln/lib/lincoln/learning/belief_formation.ex:375-393` — **Existing scoring formulas**. `calculate_learning_priority/1`: `uncertainty × 0.4 + evidence_gap × 0.4 + flags × 0.2`. `calculate_revision_urgency/1`: `contradiction × 0.2 + uncertainty × 0.5 + staleness × 0.3`. Import and use these, don't rewrite.
  - `apps/lincoln/lib/lincoln/substrate/attention_params.ex` (from Task 9) — Parameter struct and presets
  - `apps/lincoln/lib/lincoln/beliefs.ex` — Query active beliefs with their metadata

  **Acceptance Criteria**:
  - [ ] `score_belief/3` returns float 0.0-1.0 for any valid belief
  - [ ] `@focused` params: same belief stays at top for longer (high focus_momentum)
  - [ ] `@butterfly` params: top belief changes frequently (high boredom_decay)
  - [ ] Two agents with different params, same beliefs → different `:next_thought` results
  - [ ] Attention score returned alongside belief for tier selection
  - [ ] Scoring components are individually inspectable (for dashboard)

  **QA Scenarios**:

  ```
  Scenario: Different params produce different orderings
    Tool: Bash (mix test)
    Preconditions: Test agent with 10+ beliefs
    Steps:
      1. Create two Attention processes with focused and butterfly params
      2. Call :next_thought 5 times on each
      3. Compare the sequences
    Expected Result: Sequences differ — focused repeats/lingers, butterfly jumps around
    Evidence: .sisyphus/evidence/task-12-param-divergence.txt

  Scenario: Scoring components are inspectable
    Tool: Bash (iex -S mix)
    Preconditions: Agent with beliefs running
    Steps:
      1. Call `Lincoln.Substrate.Attention.score_breakdown(pid, belief_id)`
      2. Verify returns map with individual component scores: %{recency: _, tension: _, novelty: _, staleness: _, total: _}
    Expected Result: All components visible, sum to total
    Evidence: .sisyphus/evidence/task-12-score-breakdown.txt
  ```

  **Commit**: YES
  - Message: `feat(attention): add parameterized scoring replacing round-robin`
  - Files: `substrate/attention.ex`, test file
  - Pre-commit: `mix test`

- [x] 13. Tiered Inference in Driver

  **What to do**:
  - Update Driver (from Task 5) to use `InferenceTier.select_tier/2` based on the attention_score returned by Attention
  - When executing a thought:
    - **Level 0 (`:local`)**: Driver does local computation only — updates `current_focus` in Substrate, recalculates belief metadata, logs event. No model call.
    - **Level 1 (`:ollama`)**: Driver calls Ollama via adapter — "Reflect on this belief: [statement]. What's interesting about it? Are there tensions or connections you notice?" Parse response, create a memory or belief revision event.
    - **Level 2 (`:claude`)**: Driver calls Claude — "Given these beliefs [context], deeply analyze [focus belief]. Look for contradictions, novel connections, and insights." Parse response, create belief revision events.
  - LLM calls must be async via `Task.Supervisor` (add to per-agent supervision tree) — Driver sends task, continues ticking, handles result in `handle_info`
  - Add `Lincoln.Substrate.TaskSupervisor` to per-agent supervision tree (Task.Supervisor for async work)
  - When LLM result arrives, create appropriate events (new belief, belief revision, new memory) via existing context modules

  **Must NOT do**:
  - Block on LLM calls — async only
  - Skip Level 0 optimization — most ticks MUST be free
  - Modify existing belief/memory creation logic — use existing context functions

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 12, 14)
  - **Blocks**: None
  - **Blocked By**: Tasks 5, 10, 11

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/driver.ex` (from Task 5) — Extend with tiered execution
  - `apps/lincoln/lib/lincoln/substrate/inference_tier.ex` (from Task 11) — Tier selection + dispatch
  - `apps/lincoln/lib/lincoln/adapters/llm/ollama.ex` (from Task 10) — Ollama adapter for Level 1
  - `apps/lincoln/lib/lincoln/adapters/llm.ex` — Anthropic adapter for Level 2
  - `apps/lincoln/lib/lincoln/beliefs.ex` — `create_belief/1`, `revise_belief/2` for creating outputs
  - `apps/lincoln/lib/lincoln/memory.ex` — `record_memory/1` for storing reflections
  - `apps/lincoln/lib/lincoln/autonomy/token_budget.ex` — Check budget before Level 2 calls

  **Acceptance Criteria**:
  - [ ] Low attention score (< 0.3): Driver does local computation, no HTTP calls
  - [ ] Medium score (0.3-0.7): Driver calls Ollama, creates memory from response
  - [ ] High score (> 0.7): Driver calls Claude, creates belief revision from response
  - [ ] LLM calls are async — Driver tick doesn't block
  - [ ] Token budget `:minimal` forces Level 0 regardless of score
  - [ ] Ollama unavailable → falls back to Claude (or Level 0 if budget is low)

  **QA Scenarios**:

  ```
  Scenario: Three-tier execution over 10 ticks
    Tool: Bash (iex -S mix)
    Preconditions: Agent with varied beliefs, Ollama running
    Steps:
      1. Start agent substrate
      2. Let it run for 10 ticks (~50 seconds)
      3. Query Driver state for action_history
      4. Count actions by tier: local, ollama, claude
    Expected Result: Majority local (Level 0), some ollama, few/no claude
    Evidence: .sisyphus/evidence/task-13-tiered-execution.txt

  Scenario: LLM calls don't block ticks
    Tool: Bash (mix test)
    Preconditions: Mock LLM with 5-second delay
    Steps:
      1. Start Driver, trigger Level 1 execution
      2. Immediately trigger another tick
      3. Verify second tick processes while first LLM call is pending
    Expected Result: Ticks don't stall on LLM latency
    Evidence: .sisyphus/evidence/task-13-non-blocking.txt
  ```

  **Commit**: YES
  - Message: `feat(attention): add tiered inference to Driver with async LLM calls`
  - Files: `substrate/driver.ex`, `substrate/agent_supervisor.ex` (add Task.Supervisor), test file
  - Pre-commit: `mix test`

- [x] 14. Attention Parameter Dashboard Controls

  **What to do**:
  - Extend the substrate LiveView (from Task 8) with:
    - Attention score visualization: show current belief scores as a ranked list with score breakdown (recency, tension, novelty, staleness components)
    - Parameter controls: sliders or inputs for each attention param (novelty_weight, focus_momentum, interrupt_threshold, boredom_decay, depth_preference)
    - Preset buttons: "Focused", "Butterfly", "ADHD-like" that fill in preset values
    - Apply button: saves params to agent record and notifies Attention process to reload
    - Tier distribution: simple counter showing how many ticks were Level 0/1/2
  - Real-time updates via PubSub `:attention` topic — scores refresh on each tick

  **Must NOT do**:
  - Build complex data visualization (charts, graphs) — simple ranked lists and counters
  - Modify existing dashboard pages

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 12, 13)
  - **Blocks**: None
  - **Blocked By**: Tasks 8, 9

  **References**:
  - `apps/lincoln/lib/lincoln_web/live/substrate_live.ex` (from Task 8) — Extend this LiveView
  - `apps/lincoln/lib/lincoln_web/live/autonomy_live.ex` — Study the session control pattern (start/stop buttons, config forms)
  - `apps/lincoln/lib/lincoln/substrate/attention_params.ex` (from Task 9) — Presets and validation
  - `apps/lincoln/assets/css/app.css` — daisyUI form components, range inputs

  **Acceptance Criteria**:
  - [ ] Sliders/inputs for all 5 attention parameters render correctly
  - [ ] Preset buttons fill in correct values
  - [ ] Apply saves to DB and Attention process reloads params
  - [ ] Belief score ranking updates in real-time
  - [ ] Tier distribution counter shows Level 0/1/2 counts

  **QA Scenarios**:

  ```
  Scenario: Change attention params and see different behavior
    Tool: Playwright
    Preconditions: Phoenix server running, agent substrate active
    Steps:
      1. Navigate to /substrate
      2. Note current top-scored belief
      3. Click "Butterfly" preset button
      4. Click "Apply"
      5. Wait 30 seconds
      6. Note top-scored belief — should differ from step 2
      7. Screenshot
    Expected Result: Different preset produces visibly different scoring
    Evidence: .sisyphus/evidence/task-14-param-controls.png
  ```

  **Commit**: YES
  - Message: `feat(attention): add parameter controls and score visualization to dashboard`
  - Files: `live/substrate_live.ex`
  - Pre-commit: `mix test`

---

### WAVE 6 — Step 3 Scaffolding (After Wave 5)

- [x] 15. Belief Relationships Migration + Schema

  **What to do**:
  - Create migration for `belief_relationships` table:
    - `id` (binary_id, primary key)
    - `agent_id` (references agents, not null)
    - `source_belief_id` (references beliefs, not null)
    - `target_belief_id` (references beliefs, not null)
    - `relationship_type` (string: "supports", "contradicts", "refines", "depends_on", "related")
    - `confidence` (float 0.0-1.0 — how confident the system is about this relationship)
    - `detected_by` (string: "skeptic", "resonator", "manual", "inference")
    - `evidence` (text — why this relationship was detected)
    - timestamps
  - Create indexes on `source_belief_id`, `target_belief_id`, `agent_id`
  - Create unique composite index on `[source_belief_id, target_belief_id, relationship_type]`
  - Create Ecto schema `Lincoln.Beliefs.BeliefRelationship` with:
    - `belongs_to :source_belief, Lincoln.Beliefs.Belief`
    - `belongs_to :target_belief, Lincoln.Beliefs.Belief`
    - `belongs_to :agent, Lincoln.Agents.Agent`
  - Add `has_many :outgoing_relationships` and `has_many :incoming_relationships` to Belief schema
  - Add context functions to `Lincoln.Beliefs`:
    - `create_relationship/1`
    - `find_relationships/2` (for a given belief)
    - `find_contradictions/1` (relationships where type is "contradicts")
    - `find_support_cluster/1` (beliefs connected by "supports" edges)
  - Consider upgrading pgvector index from IVFFlat to HNSW for better dynamic insert performance (optional, assess during implementation)

  **Must NOT do**:
  - Modify existing `beliefs` table
  - Modify existing `contradicted_by_id` column — the new relationships table is a richer parallel structure
  - Add graph database dependency — Postgres + this table is sufficient

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 6 (with Tasks 16, 17 — but 16/17 depend on this completing first)
  - **Blocks**: Tasks 16, 17
  - **Blocked By**: None

  **References**:
  - Context7 Ecto docs: Self-referential many_to_many pattern — `join_through: Relationship, join_keys: [source_belief_id: :id, target_belief_id: :id]`
  - `apps/lincoln/lib/lincoln/beliefs/belief.ex` — Existing belief schema. Add `has_many :outgoing_relationships` and `has_many :incoming_relationships` here.
  - `apps/lincoln/priv/repo/migrations/20260326145816_create_beliefs.exs` — Existing beliefs migration. Study for naming conventions.
  - `apps/lincoln/lib/lincoln/beliefs.ex` — Beliefs context. Add new query functions here.
  - Context7 pgvector docs: HNSW index — `CREATE INDEX ON beliefs USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64)`

  **Acceptance Criteria**:
  - [ ] Migration up/down works cleanly
  - [ ] `create_relationship(%{source_belief_id: a, target_belief_id: b, relationship_type: "contradicts", agent_id: agent_id})` succeeds
  - [ ] `find_contradictions(agent)` returns beliefs connected by "contradicts" edges
  - [ ] `find_support_cluster(belief)` returns connected "supports" subgraph
  - [ ] Unique index prevents duplicate relationships
  - [ ] Existing belief tests pass

  **QA Scenarios**:

  ```
  Scenario: Create and query belief relationships
    Tool: Bash (mix test)
    Preconditions: Test agent with beliefs
    Steps:
      1. Create 3 beliefs: A, B, C
      2. Create relationship: A contradicts B
      3. Create relationship: A supports C
      4. Query find_contradictions for A — should return B
      5. Query find_support_cluster for A — should return C
      6. Attempt duplicate relationship — should fail (unique index)
    Expected Result: All CRUD and query operations work
    Evidence: .sisyphus/evidence/task-15-belief-relationships.txt
  ```

  **Commit**: YES
  - Message: `feat(skeptic): add belief_relationships table and schema`
  - Files: migration, `beliefs/belief_relationship.ex`, `beliefs/belief.ex` (add associations), `beliefs.ex` (add functions), test file
  - Pre-commit: `mix test`

- [x] 16. Skeptic GenServer

  **What to do**:
  - Create `lib/lincoln/substrate/skeptic.ex` — GenServer that runs in background looking for contradictions
  - Tick loop (slower than Substrate — default 30s, configurable): on each tick, pick a high-confidence active belief and attempt to falsify it
  - Falsification process (Level 0 — no LLM):
    1. Find beliefs that are semantically similar (via `find_similar_beliefs/3` using embeddings)
    2. Compare their statements — do they agree or disagree? Use source types and confidence levels as heuristics.
    3. Check if any recently-revised beliefs contradict the target
    4. Check if the belief's evidence is stale (source was testimony, long time since reinforcement)
  - When contradiction detected:
    1. Create a `belief_relationship` record with type "contradicts"
    2. Broadcast via PubSub `:skeptic` topic
    3. The Attention process will notice this on its next scoring cycle (higher tension = higher score)
  - Register via `{:via, Registry, {Lincoln.AgentRegistry, {agent_id, :skeptic}}}`
  - Priority: lower than Substrate/Attention/Driver — Skeptic should NOT compete for resources. Use a longer tick interval.

  **Must NOT do**:
  - Call LLM for contradiction detection in Step 3 (Level 0 only — heuristic detection)
  - Resolve contradictions — Skeptic only DETECTS and FLAGS. Resolution happens when Driver picks up the flagged belief.
  - Modify existing `belief_revision.ex` — use its functions
  - Replace the existing `BeliefMaintenanceWorker` — Skeptic runs alongside it

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - Requires understanding of belief semantics, embedding similarity, heuristic contradiction detection

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 6 (with Task 17, after Task 15)
  - **Blocks**: Tasks 18, 19
  - **Blocked By**: Tasks 3, 15

  **References**:
  - `apps/lincoln/lib/lincoln/beliefs.ex` — `find_potential_contradictions/3` (existing heuristic), `find_similar_beliefs/3` (embedding search). Skeptic calls these.
  - `apps/lincoln/lib/lincoln/cognition/belief_revision.ex` — `calculate_revision_threshold/1`, `calculate_evidence_score/2`, `source_weight/1`. Use for scoring contradiction severity.
  - `apps/lincoln/lib/lincoln/workers/belief_maintenance_worker.ex` — Existing cron-based maintenance. Study its decay logic. Skeptic is the continuous version of this.
  - `apps/lincoln/lib/lincoln/beliefs/belief_relationship.ex` (from Task 15) — Write contradiction records here
  - `apps/lincoln/lib/lincoln/substrate/substrate.ex` — Follow same OTP patterns

  **Acceptance Criteria**:
  - [ ] Skeptic starts and ticks independently (30s default interval)
  - [ ] Given beliefs "X is true" and "X is false" with high similarity: Skeptic detects contradiction within 5 ticks
  - [ ] Contradiction creates `belief_relationship` record with type "contradicts"
  - [ ] PubSub `:skeptic` topic receives flag broadcast
  - [ ] Skeptic does NOT resolve contradictions — only flags them
  - [ ] Skeptic does NOT call any LLM

  **QA Scenarios**:

  ```
  Scenario: Skeptic detects seeded contradiction
    Tool: Bash (mix test)
    Preconditions: Agent with contradictory beliefs seeded
    Steps:
      1. Create belief A: "Elixir is dynamically typed" (confidence: 0.9)
      2. Create belief B: "Elixir is statically typed" (confidence: 0.8)
      3. Generate embeddings for both (high similarity expected)
      4. Start Skeptic for this agent
      5. Trigger 5 ticks via send(pid, :tick)
      6. Query belief_relationships for type "contradicts"
    Expected Result: At least one contradiction relationship between A and B
    Evidence: .sisyphus/evidence/task-16-skeptic-contradiction.txt

  Scenario: Skeptic doesn't flag non-contradictory beliefs
    Tool: Bash (mix test)
    Preconditions: Agent with unrelated beliefs
    Steps:
      1. Create belief A: "The sky is blue" and belief B: "Elixir uses the BEAM"
      2. Start Skeptic, trigger 5 ticks
      3. Query belief_relationships
    Expected Result: No contradiction relationships created
    Evidence: .sisyphus/evidence/task-16-skeptic-no-false-positive.txt
  ```

  **Commit**: YES
  - Message: `feat(skeptic): add Skeptic GenServer with heuristic contradiction detection`
  - Files: `substrate/skeptic.ex`, test file
  - Pre-commit: `mix test`

- [x] 17. Resonator GenServer

  **What to do**:
  - Create `lib/lincoln/substrate/resonator.ex` — GenServer that detects unexpected coherences and "interesting" belief regions
  - Tick loop (slow — default 60s, configurable): on each tick, scan a region of the belief graph for coherence patterns
  - Coherence cascade detection (Level 0 — no LLM, crude v1):
    1. Find clusters of beliefs that are semantically similar (embedding cosine similarity > threshold)
    2. Within each cluster, check if recent changes to one belief (confidence change, revision) correlate with changes to others
    3. A "cascade" is when 3+ beliefs in a cluster were all revised within a short time window — suggests the topic is active and generating structure
    4. Score the cascade: `cascade_score = num_beliefs_affected × avg_confidence_change × recency_bonus`
  - When cascade detected:
    1. Create `belief_relationship` records with type "supports" between the cluster members
    2. Broadcast via PubSub `:resonator` topic with cascade details
    3. Attention process will weight candidates from this region more heavily (this is what "getting hooked on a topic" looks like)
  - Register via `{:via, Registry, {Lincoln.AgentRegistry, {agent_id, :resonator}}}`

  **Must NOT do**:
  - Try to make cascade detection perfect — this will be crude in v1, and that's fine. Get it existing, then refine.
  - Call LLM for coherence assessment (Level 0 only)
  - Resolve or create beliefs — Resonator only FLAGS interesting regions

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []
    - Novel algorithm design (coherence cascade), embedding clustering, temporal correlation

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 6 (with Task 16, after Task 15)
  - **Blocks**: Tasks 18, 19
  - **Blocked By**: Tasks 3, 15

  **References**:
  - `apps/lincoln/lib/lincoln/beliefs.ex` — `find_similar_beliefs/3` for embedding-based clustering
  - `apps/lincoln/lib/lincoln/beliefs/belief_revision.ex` (Ecto schema) — Query revision history to detect temporal correlation of changes
  - `apps/lincoln/lib/lincoln/adapters/embeddings.ex` — `compute_similarity/2` for comparing belief embeddings
  - `apps/lincoln/lib/lincoln/beliefs/belief_relationship.ex` (from Task 15) — Write "supports" records
  - Architecture sketch "The Resonator" section — "scans the belief graph for regions where small changes have produced large structural reorganizations"

  **Acceptance Criteria**:
  - [ ] Resonator starts and ticks independently (60s default)
  - [ ] Given 5 beliefs in same topic, all revised within last hour: Resonator detects cascade within 3 ticks
  - [ ] Cascade creates "supports" relationships between cluster members
  - [ ] PubSub `:resonator` topic receives cascade flag with score
  - [ ] No false positives on unrelated beliefs (different embeddings, different revision times)
  - [ ] No LLM calls

  **QA Scenarios**:

  ```
  Scenario: Resonator detects coherence cascade
    Tool: Bash (mix test)
    Preconditions: Agent with belief cluster seeded
    Steps:
      1. Create 5 beliefs about "Elixir concurrency" with high embedding similarity
      2. Simulate recent revisions on all 5 (updated within last hour)
      3. Start Resonator, trigger 3 ticks
      4. Query belief_relationships for type "supports"
    Expected Result: Support relationships created between cluster members, cascade broadcast sent
    Evidence: .sisyphus/evidence/task-17-resonator-cascade.txt

  Scenario: Resonator ignores unrelated beliefs
    Tool: Bash (mix test)
    Preconditions: Agent with diverse, unrelated beliefs
    Steps:
      1. Create 5 beliefs about completely different topics
      2. Start Resonator, trigger 3 ticks
      3. Query belief_relationships
    Expected Result: No support relationships created
    Evidence: .sisyphus/evidence/task-17-resonator-no-false-positive.txt
  ```

  **Commit**: YES
  - Message: `feat(resonator): add Resonator GenServer with coherence cascade detection`
  - Files: `substrate/resonator.ex`, test file
  - Pre-commit: `mix test`

---

### WAVE 7 — Step 3 Integration (After Wave 6)

- [ ] 18. Extend Per-Agent Supervisor to 5 Processes

  **What to do**:
  - Update `Lincoln.Substrate.AgentSupervisor` (from Task 6) to start all 5 processes: Substrate, Attention, Driver, Skeptic, Resonator
  - Update `Lincoln.Substrate.start_agent/1` public API to reflect 5 processes
  - Add `get_process/2` helper: `Lincoln.Substrate.get_process(agent_id, :skeptic)` — looks up any process by type via Registry
  - Verify `:one_for_all` restart strategy works correctly with 5 processes

  **Must NOT do**:
  - Change the public API shape from Task 6 (start_agent, stop_agent, etc. stay the same)

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 7 (with Tasks 19, 20)
  - **Blocks**: Tasks 21, 22
  - **Blocked By**: Tasks 6, 16, 17

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/agent_supervisor.ex` (from Task 6) — Extend children list
  - `apps/lincoln/lib/lincoln/substrate.ex` (from Task 6) — Update public API

  **Acceptance Criteria**:
  - [ ] `Lincoln.Substrate.start_agent(id)` starts 5 processes
  - [ ] All 5 registered in Registry
  - [ ] `Lincoln.Substrate.get_process(id, :skeptic)` returns PID
  - [ ] Stop agent terminates all 5

  **Commit**: YES
  - Message: `feat(substrate): extend per-agent supervisor to 5 processes`
  - Files: `substrate/agent_supervisor.ex`, `substrate.ex`, test file
  - Pre-commit: `mix test`

- [ ] 19. Wire Skeptic/Resonator Flags into Attention Scoring

  **What to do**:
  - Update Attention GenServer (from Task 12) to incorporate Skeptic and Resonator signals:
    - Beliefs flagged by Skeptic (have "contradicts" relationships) get a tension bonus in scoring
    - Beliefs flagged by Resonator (in a cascade cluster, have "supports" relationships) get a novelty/interest bonus
    - Query `belief_relationships` on each scoring cycle (or cache relationships in Attention state, refresh periodically)
  - New scoring components:
    - `contradiction_bonus`: if belief has contradiction relationship, bonus proportional to contradiction confidence
    - `cascade_bonus`: if belief is part of a recent cascade, bonus proportional to cascade_score
  - These bonuses are weighted by attention_params — `interrupt_threshold` controls how much Skeptic flags can disrupt current focus

  **Must NOT do**:
  - Modify Skeptic or Resonator — they just write to DB/PubSub. Attention reads.

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 7 (with Tasks 18, 20)
  - **Blocks**: None
  - **Blocked By**: Tasks 12, 16, 17

  **References**:
  - `apps/lincoln/lib/lincoln/substrate/attention.ex` (from Task 12) — Add contradiction_bonus and cascade_bonus to scoring
  - `apps/lincoln/lib/lincoln/beliefs.ex` — `find_contradictions/1`, `find_support_cluster/1` (from Task 15)

  **Acceptance Criteria**:
  - [ ] Belief with contradiction relationship scores higher (tension bonus)
  - [ ] Belief in cascade cluster scores higher (interest bonus)
  - [ ] `interrupt_threshold` param controls how much flags affect scoring
  - [ ] Scoring still works when no relationships exist (no crashes on empty graph)

  **Commit**: YES
  - Message: `feat(attention): wire Skeptic/Resonator flags into scoring`
  - Files: `substrate/attention.ex`, test file
  - Pre-commit: `mix test`

- [ ] 20. Skeptic + Resonator Dashboard Panels

  **What to do**:
  - Extend substrate LiveView (from Task 8/14) with:
    - **Skeptic panel**: list of recent contradictions detected (source belief, target belief, confidence, timestamp). Highlight currently-under-investigation belief.
    - **Resonator panel**: list of recent cascades (cluster members, cascade_score, timestamp). Visual indicator of "hot" belief regions.
    - **Belief graph visualization**: simple directed graph showing belief relationships (contradicts in red, supports in green). Can be a basic HTML/CSS layout — doesn't need D3.js for v1.
  - Subscribe to PubSub `:skeptic` and `:resonator` topics for real-time updates

  **Must NOT do**:
  - Build complex graph visualization (D3, force-directed layout, etc.) — simple list/table view is sufficient for v1
  - Modify existing dashboard pages

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 7 (with Tasks 18, 19)
  - **Blocks**: None
  - **Blocked By**: Tasks 8, 16, 17

  **References**:
  - `apps/lincoln/lib/lincoln_web/live/substrate_live.ex` (from Tasks 8, 14) — Extend
  - `apps/lincoln/lib/lincoln_web/live/beliefs_live.ex` — Study belief display patterns (confidence badges, source type indicators)

  **Acceptance Criteria**:
  - [ ] Skeptic panel shows detected contradictions with belief details
  - [ ] Resonator panel shows detected cascades with member beliefs
  - [ ] Both update in real-time via PubSub
  - [ ] Relationship list shows typed edges (contradicts/supports) between beliefs

  **Commit**: YES
  - Message: `feat(substrate): add Skeptic and Resonator panels to dashboard`
  - Files: `live/substrate_live.ex`
  - Pre-commit: `mix test`

---

### WAVE 8 — Step 4 Divergence Demo (After Wave 7)

- [ ] 21. Multi-Instance Input Broadcaster + Trajectory Recording

  **What to do**:
  - Create `lib/lincoln/substrate/input_broadcaster.ex` — module that sends the same event to multiple agent Substrate processes simultaneously
    - `broadcast_to_all(event)` — finds all running agents via `Lincoln.Substrate.list_running_agents()`, sends event to each
    - `broadcast_to_group(agent_ids, event)` — sends to specific agents
  - Create `lib/lincoln/substrate/trajectory.ex` — records and queries agent cognitive trajectories
    - Create migration: `substrate_events` table — `agent_id`, `event_type`, `event_data` (JSONB), `tick_number`, `attention_score`, `inference_tier`, `timestamp`
    - Wire into Substrate: on each tick, record what happened (what was focused on, what the attention score was, what the driver did)
    - `compare_trajectories(agent_id_1, agent_id_2, time_range)` — returns side-by-side event lists
    - `trajectory_summary(agent_id, time_range)` — returns: top topics, belief revisions, contradictions detected, cascades noticed

  **Must NOT do**:
  - Build statistical analysis — visual comparison is sufficient
  - Build sync mechanisms between instances — they run independently

  **Recommended Agent Profile**:
  - **Category**: `deep`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 8 (with Task 22)
  - **Blocks**: Task 23
  - **Blocked By**: Task 18

  **References**:
  - `apps/lincoln/lib/lincoln/substrate.ex` (from Task 6) — `list_running_agents/0`, `send_event/2`
  - `apps/lincoln/lib/lincoln/events/cache.ex` — Event recording patterns

  **Acceptance Criteria**:
  - [ ] `broadcast_to_all(event)` delivers event to all running agents
  - [ ] `substrate_events` table records per-tick data including attention score and tier
  - [ ] `compare_trajectories/3` returns aligned event lists for two agents
  - [ ] Migration up/down clean

  **Commit**: YES
  - Message: `feat(demo): add input broadcaster and trajectory recording`
  - Files: `substrate/input_broadcaster.ex`, `substrate/trajectory.ex`, migration, test files
  - Pre-commit: `mix test`

- [ ] 22. Comparison LiveView at /substrate/compare

  **What to do**:
  - Create `lib/lincoln_web/live/substrate_compare_live.ex` at route `/substrate/compare`
  - Side-by-side layout showing two agent instances:
    - Left panel: Agent A with its attention params, current focus, recent actions, tick count
    - Right panel: Agent B with the same
    - Center: shared timeline showing when the same input was delivered
  - Agent selector: dropdown to pick which two agents to compare
  - Real-time: subscribe to both agents' PubSub topics, update both panels live
  - Trajectory diff: show where the two agents diverged — highlight moments where the same input produced different attention scores, different focus choices, different tier selections
  - This is THE demo page. The thing someone visits to watch two digital substrates diverge in real time.

  **Must NOT do**:
  - Build complex animations or transitions — clean, readable layout is more important
  - Require specific agents — any two running agents can be compared

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 8 (with Task 21)
  - **Blocks**: Task 23
  - **Blocked By**: Tasks 8, 18

  **References**:
  - `apps/lincoln/lib/lincoln_web/live/substrate_live.ex` — Base pattern for substrate display
  - `apps/lincoln/lib/lincoln/substrate/trajectory.ex` (from Task 21) — `compare_trajectories/3` for diff data

  **Acceptance Criteria**:
  - [ ] `/substrate/compare` loads with agent selector
  - [ ] Selecting two agents shows side-by-side real-time state
  - [ ] Both panels update independently via PubSub
  - [ ] Trajectory diff highlights divergence points

  **QA Scenarios**:

  ```
  Scenario: Watch two agents diverge in real time
    Tool: Playwright
    Preconditions: Two agents running with different attention params (focused vs butterfly)
    Steps:
      1. Navigate to /substrate/compare
      2. Select Agent A (focused) and Agent B (butterfly)
      3. Wait 60 seconds, taking screenshots every 15 seconds
      4. Verify both panels show different current_focus values
      5. Verify tick counts are advancing for both
    Expected Result: Two agents visibly processing differently despite same starting conditions
    Evidence: .sisyphus/evidence/task-22-comparison-live.png
  ```

  **Commit**: YES
  - Message: `feat(demo): add side-by-side comparison LiveView`
  - Files: `live/substrate_compare_live.ex`, `router.ex`
  - Pre-commit: `mix test`

- [ ] 23. Demo Seed Script

  **What to do**:
  - Create `lib/mix/tasks/lincoln.demo.divergence.ex` — Mix task that sets up and runs the divergence demo
  - Script:
    1. Create (or find) two agents: "Lincoln-Focused" with `@focused` attention params, "Lincoln-Butterfly" with `@butterfly` params
    2. Seed both with the same initial beliefs (5-10 diverse beliefs across different topics)
    3. Start both agent substrate processes
    4. Send the same sequence of 10 input events to both (via input broadcaster)
    5. Let them run for N minutes (configurable, default 5 for quick demo)
    6. Print trajectory summary for both agents side-by-side
    7. Print divergence analysis: which beliefs each focused on, which contradictions each found, which topics each developed interest in
  - Output should be compelling enough to include in a writeup
  - Also print: "Open http://localhost:4000/substrate/compare to watch live"

  **Must NOT do**:
  - Require specific external input (RSS feeds, etc.) — self-contained seed data
  - Run for hours by default — 5 minutes is enough for a demo
  - Build fancy output formatting — plain text terminal output is fine

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (after Tasks 21, 22)
  - **Blocks**: None
  - **Blocked By**: Tasks 21, 22

  **References**:
  - `apps/lincoln/lib/lincoln/substrate.ex` — `start_agent/1`, `send_event/2`
  - `apps/lincoln/lib/lincoln/substrate/input_broadcaster.ex` (from Task 21) — `broadcast_to_group/2`
  - `apps/lincoln/lib/lincoln/substrate/trajectory.ex` (from Task 21) — `compare_trajectories/3`, `trajectory_summary/2`
  - `apps/lincoln/lib/lincoln/substrate/attention_params.ex` (from Task 9) — Presets

  **Acceptance Criteria**:
  - [ ] `mix lincoln.demo.divergence` runs end-to-end without errors
  - [ ] Output shows two agents processing the same input differently
  - [ ] Trajectory summaries show different top topics, different belief revision counts
  - [ ] Prints URL for live comparison view

  **QA Scenarios**:

  ```
  Scenario: Full divergence demo
    Tool: Bash
    Preconditions: Database migrated, Ollama running (optional)
    Steps:
      1. Run `mix lincoln.demo.divergence --minutes 2`
      2. Verify output shows two agent summaries
      3. Verify the summaries are different (different top topics, different revision counts)
      4. Verify exit code 0
    Expected Result: Complete demo run with visible divergence
    Evidence: .sisyphus/evidence/task-23-demo-output.txt
  ```

  **Commit**: YES
  - Message: `feat(demo): add mix lincoln.demo.divergence seed script`
  - Files: `lib/mix/tasks/lincoln.demo.divergence.ex`
  - Pre-commit: `mix test`

---

## Final Verification Wave

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results to user and get explicit "okay" before completing.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read `.sisyphus/plans/lincoln-substrate.md` end-to-end. For each "Must Have": verify implementation exists (read file, query state via iex, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in `.sisyphus/evidence/`. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `mix compile --warnings-as-errors` + `mix credo` + `mix test`. Review all new files in `lib/lincoln/substrate/` for: `as any` equivalents, empty rescue clauses, IO.inspect in prod, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names. Verify all GenServer modules implement proper `terminate/2` and handle unknown messages gracefully.
  Output: `Build [PASS/FAIL] | Credo [PASS/FAIL] | Tests [N pass/N fail] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high` (+ `playwright` skill for LiveView)
  Start from `mix ecto.reset && mix phx.server`. Start an agent process tree via iex. Execute EVERY QA scenario from EVERY task — follow exact steps, capture evidence. Test cross-task integration: send conversation event, verify Substrate receives it, Attention scores it, Driver processes it. Test the divergence demo end-to-end. Save to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff (git log/diff). Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no creep). Check "Must NOT do" compliance — especially: no modification of conversation_handler.ex internals, no modification of existing Oban workers, no umbrella restructuring. Flag unaccounted changes.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VERDICT`

---

## Commit Strategy

Each task lists its own commit message. General pattern:
- **Step 1**: `feat(substrate): ...` — foundation
- **Step 2**: `feat(attention): ...` — parameterization + Ollama
- **Step 3**: `feat(skeptic): ...` / `feat(resonator): ...` — background processes
- **Step 4**: `feat(demo): ...` — divergence demo

---

## Success Criteria

### Verification Commands
```bash
mix compile --warnings-as-errors  # Expected: 0 warnings
mix test                          # Expected: all pass
mix credo --strict                # Expected: 0 issues
```

### Property Tests (the "Done When" from the architecture sketch)
1. **Continuity**: Lincoln runs 24h, DB has non-trivial changes from autonomous cognition
2. **Self-generated**: Leave Lincoln alone, come back, it did things that weren't scheduled
3. **Differential**: Two instances with different params produce different trajectories on same input
4. **Tunable**: Editing attention params and restarting produces visibly different behavior

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] All existing tests still pass (`mix test`)
- [ ] New GenServer processes start and tick without errors for 10 minutes
- [ ] Ollama adapter responds successfully to health check
- [ ] Dashboard shows real-time cognitive state
- [ ] Comparison view shows two diverging instances
