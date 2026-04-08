# LEARNINGS.md — Where Lincoln Actually Is

An honest audit of the codebase as of build completion (Steps 1-7 done). Written for the builder, not the public.

Last updated: 2026-04-08

---

## What Was Built (Steps 1-7)

### Step 1: Thoughts as Processes
Each substrate tick spawns a `Thought` GenServer under a per-agent `ThoughtSupervisor`. Thoughts are first-class OTP processes with lifecycle (initializing → executing → awaiting_llm / awaiting_children → completed / failed / interrupted). Visible at `/substrate/thoughts`.

### Step 2: Interruption
`interrupt_threshold` from `attention_params` controls whether a running thought gets preempted by a higher-scoring belief. `focused` (0.8) rarely interrupts. `butterfly` (0.3) interrupts constantly. Implemented in `Substrate.spawn_thought/3`.

### Step 3: Child Thoughts
LLM-tier thoughts check `belief_relationships` for related beliefs. If found, spawn Level 0 child thoughts in parallel, wait for all to complete via PubSub, then synthesize with the parent LLM call. Children are never grandchildren — `parent_id` guard prevents recursion. Dashboard shows tree with children indented.

### Step 4: Theory of Mind
`user_models` table. `ConversationBridge.notify/3` calls `UserModels.observe_message/3` on every chat message. Extracts topics, counts questions, infers vocabulary style. Chat LiveView shows "WHAT LINCOLN KNOWS ABOUT YOU" panel.

### Step 5: Narrative Reflections
Every 200 substrate ticks, a narrative Thought is spawned with `is_narrative: true`. Uses Claude with an introspective first-person prompt. Persists to `narrative_reflections` table. `/narrative` shows Lincoln's autobiography.

### Step 6: Self-Model
`self_model` table (single row per agent). Updated every 50 ticks from `substrate_events` and `narrative_reflections`. Tracks: total/completed/failed thoughts, tier distribution, ticks, narrative count. Displayed as a widget in `/substrate` dashboard.

### Step 7: Quantitative Metrics
`benchmark_runs` + `benchmark_results` tables. 20 contradiction detection tasks. `mix lincoln.benchmark.run` runs the benchmark and records accuracy. `/benchmarks` shows historical runs.

---

## Current Architecture (Accurate as of Today)

```
Per agent, under DynamicSupervisor:
├── Substrate (5s ticks) — orchestrates the tick cycle, spawns Thoughts
├── Attention (on-demand) — parameterized belief scoring
├── Driver (on-demand, mostly retired) — legacy execution; Thoughts now own execution
├── Skeptic (30s) — contradiction detection via embeddings
├── Resonator (60s) — coherence cascade detection
└── ThoughtSupervisor (DynamicSupervisor) — manages Thought processes
    ├── Thought (ephemeral) — individual cognitive acts
    ├── Thought (ephemeral)
    └── ...
```

---

## Known Limitations (Honest)

### 1. Substrate still polls (5s timer)
Events arrive via `handle_cast` and are queued. Processing waits for the next tick. High-priority events don't get immediate processing. "Continuity" is periodic, not truly continuous.

### 2. Oban workers run alongside substrate
`AutonomousLearningWorker` (30s cycle), `BeliefMaintenanceWorker` (daily), `CuriosityWorker` (hourly), `ReflectionWorker` (6h) still run. They overlap with substrate cognition. **Fix applied**: AutonomousLearningWorker now skips if substrate is active for the agent.

### 3. Interrupt threshold can be stale
`get_interrupt_threshold/1` reloads from DB on each call now (fixed). But Attention's `attention_params` in state is only loaded on init — `reload_params` cast is required after runtime param changes.

### 4. Resonator grouping is crude
Groups beliefs by `source_type` as a proxy for topical coherence. Will produce false positives. This is a known v1 limitation.

### 5. Conversation bypasses substrate for response
ConversationHandler generates the LLM response. ConversationBridge notifies substrate after the fact. Substrate influences future cognition but not the current response.

### 6. Trajectory data incomplete in some paths
`thought_completed`/`thought_failed` events record to trajectory. But thought interruptions and child thought details aren't always captured in the summary. `Trajectory.summary/2` gives a reasonable picture but not a complete one.

### 7. Token budget not integrated into Driver
Driver always uses `:full` budget when selecting inference tier. `TokenBudget.suggest_operations/1` exists but isn't consulted. A minimal-budget agent would use Level 0 for everything regardless of attention score.

---

## What Remains Before Writeup Ships

1. **Run the system** — Actually run Lincoln, observe 24h of autonomous operation, capture trajectory data
2. **Run the divergence demo** — `mix lincoln.demo.divergence --minutes 60`, screenshot `/substrate/compare`
3. **Run the benchmark** — `mix lincoln.benchmark.run`, capture accuracy numbers
4. **Polish the writeup** — Add real numbers from actual runs to `writeup.md`
