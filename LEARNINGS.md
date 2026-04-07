# LEARNINGS.md — Where Lincoln Actually Is

An honest audit of the gap between what the README claims, what the master plan requires, and what the code actually does. Written for the builder, not the public.

Last audited: 2026-04-07

---

## Audit 1: Substrate Continuity

**Claim**: "Something is always running"
**Reality**: The substrate sleeps between ticks.

`Process.send_after(self(), :tick, 5000)` → 5 seconds of nothing → tick fires → work → sleep again. Between tick N and tick N+1, the process is idle. Events arrive via `handle_cast({:event, event})` but are only **queued**, not **processed** — processing waits for the next tick.

**What needs to change**: Events should trigger immediate processing (not wait for next tick). The substrate should have inter-tick state evolution — activation decay, focus drift, working memory maintenance. The master plan says "continuous means continuous, not polls every 5 seconds and otherwise sleeps." The current code is the latter.

**Specific fix**: Add `handle_cast({:event, event})` processing that does more than append to queue — at minimum, update activation_map immediately and possibly trigger an out-of-cycle attention evaluation for high-priority events.

---

## Audit 2: Attention Scoring

**Claim**: Parameterized scoring with cognitive style differentiation
**Reality**: ✅ All five parameters present and functional

- `novelty_weight` — weights novel/unexplored beliefs ✅
- `focus_momentum` — boosts currently-focused belief ✅
- `interrupt_threshold` — scales contradiction bonus (how much Skeptic flags disrupt focus) ✅
- `boredom_decay` — weights stale beliefs ✅
- `depth_preference` — weights core/entrenched beliefs ✅

The scoring function (attention.ex lines 213-226) combines novelty, tension, staleness, depth, contradiction_bonus, and cascade_bonus. The formula is reasonable. Different presets (focused/butterfly/adhd_like) produce different orderings — this was tested.

**One gap**: The `interrupt_threshold` parameter doesn't actually control *interruption* of running thoughts (thoughts-as-processes doesn't exist yet). It only scales how much contradiction flags boost a belief's attention score. Real interruption requires thoughts-as-processes.

---

## Audit 3: Driver → Thought Refactoring Path

**Current**: Attention picks a belief → calls Driver.execute → Driver does local work or spawns async Task for LLM.
**Needed**: Attention picks a belief → spawns a Thought process → Thought manages its own lifecycle.

The cleanest refactor: **Thought replaces Driver**. The Driver's current logic becomes utility functions that Thoughts call. Specifically:

- `do_local_execution/2` (driver.ex:179-208) → becomes `Thought.execute_local/2`
- `do_async_execution/3` (driver.ex:211-252) → becomes `Thought.execute_llm/3`
- The tier selection stays in `InferenceTier` (already decoupled)
- The `pending_tasks` map in Driver becomes unnecessary — each Thought manages its own Task
- The `action_history` moves to the Trajectory recorder
- The `tier_counts` move to the Substrate or a metrics module

The Driver can remain as a thin coordination layer, or be removed entirely with the Substrate calling Thoughts directly.

---

## Audit 4: Skeptic and Resonator Status

**Skeptic** — Implemented, not a stub. On each 30s tick:
1. Picks a random high-confidence belief
2. Gets its embedding (if exists)
3. Finds similar beliefs via pgvector cosine similarity
4. Checks heuristic contradiction signals (both confident + different sources OR recently challenged)
5. Creates `belief_relationship` with type "contradicts"
6. Broadcasts flag via PubSub

**Limitation**: Requires embeddings to exist on beliefs. If ML service hasn't generated embeddings, the skeptic silently skips. No LLM-based contradiction detection.

**Resonator** — Implemented, crude. On each 60s tick:
1. Groups all active beliefs by `source_type` (not semantic similarity)
2. Checks if 3+ beliefs in a group were updated within 1 hour
3. Creates "supports" relationships between pairs
4. Broadcasts cascade flag

**Limitation**: Grouping by `source_type` is a very rough proxy for topical coherence. Beliefs about completely different topics with the same source_type will cluster together. The master plan acknowledges this: "Detection is crude in v1."

---

## Audit 5: Trajectory Recording

**What it records**: Per-tick only:
- `tick_count` ✅
- `current_focus_id` ✅
- `pending_events_count` ✅

**What it DOESN'T record**:
- Attention scores ❌
- Which belief was selected and why ❌
- Driver tier selection ❌
- What the Driver actually did ❌
- LLM responses ❌
- Skeptic/Resonator detections ❌
- Thought lifecycle events (spawn/complete/interrupt/fail) ❌ (thoughts don't exist yet)

**Impact on divergence demo**: The demo can show that two agents had different tick counts and different focus beliefs, but NOT *why* they diverged. You can't see "Agent A scored this belief 0.8 while Agent B scored it 0.3" because scores aren't recorded. The divergence demo needs much richer trajectory data.

**Fix**: The Substrate's tick handler should record the Attention score and Driver tier for each tick. The Driver should record its own events. Skeptic and Resonator should record their detections.

---

## Audit 6: Conversation Bridge

**How it works**: Chat message → `ConversationHandler.process_message/3` (generates LLM response) → response sent to user → THEN `ConversationBridge.notify/3` sends a `:conversation` event to the Substrate.

**The substrate does NOT generate chat responses.** It sees conversations as historical events that inform future autonomous cognition. The existing ConversationHandler pipeline (1448 lines, PERCEIVE→COMMAND→REMEMBER→REASON→DELIBERATE→RESPOND→LEARN) runs independently.

**Is this a thesis violation?** Debatable. The master plan says "a chat message must enter the substrate as an event that Attention scores." Currently it enters the substrate, but *after* the response is already generated, so Attention never scores it for the purpose of responding. For the thesis, this is OK if we're honest about it: conversations are inputs to the substrate, not outputs of it. The substrate influences *future* cognition, not the current response. The README's Current Limitations section now says this explicitly.

---

## Audit 7: Legacy Oban Workers

Six workers still running alongside the substrate:

| Worker | Schedule | What It Does | Overlaps With Substrate? |
|--------|----------|-------------|------------------------|
| `AutonomousLearningWorker` | Self-rescheduling 30s | Full learning cycle: curiosity → research → reflection → evolution | YES — this is the proto-Substrate |
| `BeliefMaintenanceWorker` | Daily 3am | Decay unused beliefs, find contradictions | YES — overlaps Skeptic |
| `CuriosityWorker` | Hourly | Generate curiosity-driven questions | Partially — could be a Thought |
| `ReflectionWorker` | Every 6h | Generate reflections on recent activity | Partially — could be a Thought |
| `InvestigationWorker` | On-demand | Deep investigation of questions | Partially — could be a Thought |
| `ObservationWorker` | On-demand | Observe code changes | No direct overlap |

**The AutonomousLearningWorker (680 lines) is the biggest concern.** It was the proto-Substrate — doing 30s tick cycles, budget checking, session lifecycle management. But it runs alongside the new Substrate processes, potentially doing conflicting work on the same agent's beliefs.

**Decision needed**: Either disable the AutonomousLearningWorker when the substrate is running (simple), absorb its logic into the substrate (medium), or remove it entirely (requires the substrate to cover all its functionality first).

---

## Audit 8: Per-Agent Isolation

**Process isolation**: ✅ Each agent gets its own supervision tree under `DynamicSupervisor`. Processes register in `Lincoln.AgentRegistry` under `{agent_id, :process_type}`. Two agents = two completely separate process trees.

**Database isolation**: ✅ All queries are scoped by `agent_id`:
- Beliefs, memories, questions — all have `agent_id` foreign key
- `list_beliefs/2` takes `%Agent{}` struct, queries by agent_id
- `find_all_relationships/1` scoped by agent_id
- `substrate_events` scoped by agent_id

**Shared state**: None. Two agents sharing a database is fine — they can't see each other's data.

---

## Audit 9: Dashboard Inventory

| Dashboard | Status | Notes |
|-----------|--------|-------|
| `/substrate` | ✅ Built | Tick counter, events, attention params, tier counts, skeptic/resonator panels |
| `/substrate/compare` | ✅ Built | Side-by-side agent comparison, divergence indicator |
| `/substrate/thoughts` | ❌ Doesn't exist | Needs to be built for thoughts-as-processes |
| `/` (Dashboard) | ✅ Pre-existing | Agent overview, system stats |
| `/chat` | ✅ Pre-existing | Chat with cognitive transparency |
| `/beliefs` | ✅ Pre-existing | Belief matrix |
| `/questions` | ✅ Pre-existing | Question tracker |
| `/memories` | ✅ Pre-existing | Memory bank |
| `/autonomy` | ✅ Pre-existing | Autonomous learning sessions |

**For the writeup**: `/substrate/compare` (the divergence demo) and `/substrate/thoughts` (live thought tree) are the two URLs people will screenshot. `/substrate/thoughts` doesn't exist yet.

---

## Audit 10: Gaps Between Claims and Reality

### Implementation diverges from README:

1. **README says "always running"** → Code sleeps between 5s ticks
2. **README says "decides what to do next"** → Substrate doesn't call Attention/Driver on idle ticks, only picks a new focus
3. **README says "three-tier inference"** → Driver records tier in `tier_counts` but trajectory doesn't capture it
4. **Trajectory.summary** claims to show tier distribution → The `inference_tier` field is always "local" because the Substrate (not the Driver) records events

### TODOs and pending items:

1. `driver.ex:13` — "NOTE: Token budget integration is pending. Currently defaults to :full."
2. `resonator.ex:9` — "Detection is crude in v1 — pure heuristic, no LLM, no embeddings."
3. No tests for the actual divergence behavior (two agents producing different trajectories)
4. No integration test that starts a full agent supervision tree and verifies all 5 processes tick

### Tests that were written but may be thin:

- `substrate_test.exs` — Tests basic tick, event queuing, state retrieval. Does NOT test inter-tick behavior or event processing logic.
- `attention_test.exs` — Tests scoring and round-robin. Does NOT test that different params produce different orderings (the core claim).
- `driver_test.exs` — Tests execution and history. Does NOT test async LLM path (would need Mox).
- `skeptic_test.exs` — Tests tick counting. Does NOT test actual contradiction detection (needs embeddings).
- `resonator_test.exs` — Tests cascade detection with seeded data. Decent coverage.

### Things the master plan requires that don't exist yet:

1. **Thoughts as processes** — The biggest gap. No `Lincoln.Substrate.Thought` module.
2. **Theory of Mind (user model)** — No `user_models` table or module.
3. **Self-model** — No self-model representation.
4. **Narrative reflections** — No `narrative_reflections` table.
5. **Quantitative metrics harness** — No benchmark infrastructure.
6. **`/substrate/thoughts` dashboard** — No LiveView for thought tree visualization.
7. **Thought interruption** — Can't interrupt running work (no thought lifecycle).
8. **Child thoughts** — No tree-of-thought process spawning.
9. **Resumable interrupted thoughts** — No checkpointing.
10. **Cognitive bias documentation** — No systematic failure mode analysis.
