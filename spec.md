# Lincoln Cognitive Substrate — 5-Issue Fix Spec

## Problem Statement

Five structural issues degrade Lincoln's cognitive quality. They are interdependent: duplicates amplify perseveration, perseveration generates redundant reflections, and the self-modification pipeline could detect and fix these patterns if it were active.

1. **Perseveration loops** — high-entrenchment beliefs dominate attention despite existing monotony penalties
2. **Memory imbalance** — 98.9% of memories are reflections; observations and conversations are sparse
3. **Duplicate beliefs** — same claim at different confidence levels passes through consolidation
4. **Investigation backlog** — 123 questions queued, processing at 1/minute
5. **Self-modification not wired** — the pipeline works but nothing feeds the ImprovementQueue

---

## Implementation Status

All code compiles cleanly (`mix compile --warnings-as-errors` passes from `apps/lincoln/`).

### Phase 1: Duplicate Beliefs — DONE

**Files modified:** `apps/lincoln/lib/lincoln/beliefs.ex`

Changes made:
- [x] Creation-time dedup via `maybe_dedup_on_create/2` — checks embedding similarity >= 0.90 before inserting; strengthens existing belief if duplicate found
- [x] Lowered consolidation thresholds: high-confidence 0.95 -> 0.90, low-confidence 0.88 -> 0.82
- [x] Multi-factor winner selection in `pick_consolidation_winner/2` — entrenchment (3x) + recency (2pts if updated in last week) + revision_count
- [x] Dedup metrics — `consolidate_similar/1` now returns `%{merged: n, checked: n}`, logs results, emits `:telemetry` event `[:lincoln, :beliefs, :consolidation]`
- [x] Added `require Logger`

### Phase 2: Perseveration Loops — DONE

**Files modified:**
- `apps/lincoln/lib/lincoln/substrate/diversity_monitor.ex` (full rewrite)
- `apps/lincoln/lib/lincoln/substrate/attention.ex`
- `apps/lincoln/lib/lincoln/substrate/attention_params.ex`

Changes made:
- [x] Shannon entropy replaces cosine-distance average — two measures: item entropy (belief-ID frequency) and topic entropy (single-linkage semantic clusters at 0.7 threshold)
- [x] Graduated response with four tiers:
  - entropy >= 0.6: healthy (restore if boosted)
  - 0.35-0.59: mild (novelty -> 0.5, dampening -> 0.3)
  - 0.15-0.34: moderate (novelty -> 0.7, dampening -> 0.6)
  - < 0.15: aggressive (novelty -> 0.85, dampening -> 0.9, suppress top-3 focused beliefs)
- [x] `entrenchment_dampening` param in Attention — reduces depth_score contribution from entrenchment: `dampened_e = belief.entrenchment * (1.0 - dampening)`
- [x] `suppressed_belief_ids` param in Attention — applies -0.8 penalty to suppressed beliefs
- [x] Fixed settled_penalty gap — added tier for `entrenchment >= 7`: penalty = `0.3 + confidence * 0.2` (e=8,c=0.6 now gets 0.42 penalty instead of 0.09)
- [x] Added `entrenchment_dampening: 0.0` and `suppressed_belief_ids: []` to all AttentionParams presets (default, focused, butterfly, adhd_like)

### Phase 3: Memory Type Imbalance — DONE

**Files modified:**
- `apps/lincoln/lib/lincoln/memory.ex`
- `apps/lincoln/lib/lincoln/substrate/thought.ex`

Changes made:
- [x] Reflection default importance lowered from 7 to 5 in `record_reflection/3`
- [x] Type-diverse retrieval in `retrieve_memories/3` — fetches 3x limit, groups by memory_type, takes `ceil(limit/type_count)` per type, re-sorts by score. Controlled by `:type_diversity` opt (default true)
- [x] `type_distribution/1` function — returns `%{"reflection" => n, "observation" => n, ...}` via grouped count query
- [x] Reflection rate limiting in `process_thought_result/4` — skips creation when >= 10 reflections exist in last 5 minutes (`@max_reflections_per_window 10`, `@reflection_window_seconds 300`)

### Phase 4: Investigation Pipeline Backlog — DONE

**Files modified:**
- `apps/lincoln/lib/lincoln/substrate/investigation_thought.ex`
- `apps/lincoln/lib/lincoln/substrate/thought.ex`
- `apps/lincoln/lib/lincoln/substrate/cognitive_impulse.ex`
- `apps/lincoln/lib/lincoln/questions.ex`
- `apps/lincoln/lib/lincoln/substrate/substrate.ex`

Changes made:
- [x] `execute_batch/2` in InvestigationThought — processes multiple questions sequentially
- [x] Batch dispatch in `run_impulse(:investigation)` — >20 pending: batch of 5, >5 pending: batch of 3, else single
- [x] Dynamic investigation cooldown — 15s when >20 pending, 60s otherwise (`investigation_cooldown/1` in CognitiveImpulse)
- [x] `count_open_questions/1` in Questions
- [x] `prune_stale_questions/2` in Questions — marks questions older than 30 days with times_asked <= 1 as "abandoned"
- [x] Question pruning wired into substrate periodic tasks at 1000-tick interval
- [x] Investigation question ordering enhanced: `[desc: :times_asked, desc: :priority, asc: :inserted_at]`

### Phase 5: Self-Modification Pipeline — PARTIALLY DONE

**Files modified:**
- `apps/lincoln/lib/lincoln/events/opportunity_detector.ex` (NEW)
- `apps/lincoln/lib/lincoln/substrate/substrate.ex`
- `apps/lincoln/lib/lincoln/autonomy/self_improvement.ex`
- `apps/lincoln/lib/lincoln/autonomy.ex`

Changes made:
- [x] `OpportunityDetector` module created with 4 detection heuristics:
  - `detect_thought_failure_rate` — >20% failure in last hour with 20+ sample
  - `detect_investigation_quality` — avg confidence <0.5 across 10+ recent investigations
  - `detect_belief_churn` — >40% retraction rate in 24h with 10+ beliefs created
  - `detect_persistent_perseveration` — entrenchment_dampening >= 0.6 (moderate+ DiversityMonitor tier active)
  - Max 5 pending opportunities, dedup by pattern
- [x] Wired into substrate at 500-tick interval
- [x] Safety guardrails in SelfImprovement:
  - Rate limit: 30-minute gap between successful modifications
  - Forbidden files: evolution.ex, self_improvement.ex, repo.ex, application.ex
  - Scope constraint: only files under `lib/lincoln/`
- [x] `most_recent_code_change/2` added to Autonomy module

**Still TODO:**
- [ ] `Evolution.rollback_change/1` — should use `git revert` on stored commit hash from CodeChange record. File: `apps/lincoln/lib/lincoln/autonomy/evolution.ex`. The CodeChange schema has a `git_commit` field (check `autonomy/code_change.ex`). Implementation: look up the change, verify it has a git_commit, run `System.cmd("git", ["revert", "--no-edit", hash])`, update status to "rolled_back".

---

## Remaining Work (Not Started)

### Tests

All phases need test coverage. Existing test files to extend:

**Phase 1 tests** — `apps/lincoln/test/lincoln/beliefs_test.exs`
- Creation-time dedup: create a belief, then create another with embedding similarity > 0.90 — should strengthen first, not create second
- Consolidation with lowered thresholds: create two beliefs with similarity 0.91 — should now merge (previously wouldn't at 0.95 threshold)
- Winner selection: create two beliefs — one with high entrenchment but old, one with lower entrenchment but recent + more revisions — recent should win

**Phase 2 tests** — `apps/lincoln/test/lincoln/substrate/attention_test.exs` + new `diversity_monitor_test.exs`
- `item_entropy/1`: verify known distributions (all same ID -> 0.0, all different -> 1.0, half-half -> 1.0)
- `topic_entropy/1`: verify clustering produces correct cluster count
- `depth_score/2` with entrenchment_dampening: e=8 belief with dampening=0.5 should score ~half of dampening=0.0
- `score_with_focus_detailed/5` with suppressed_belief_ids: suppressed belief should get near-zero final score
- Graduated response: verify each tier triggers at correct entropy level

**Phase 3 tests** — `apps/lincoln/test/lincoln/memory_test.exs`
- `type_distribution/1`: create memories of different types, verify correct counts
- Type-diverse retrieval: create 20 reflections and 2 observations with high relevance — observations should still appear in top 10 results
- `reflection_rate_exceeded?/1`: create 10 reflections in last minute, verify returns true; create 9, verify false

**Phase 4 tests** — `apps/lincoln/test/lincoln/questions_test.exs`
- `execute_batch/2`: mock LLM, create 5 open questions, batch process 3, verify 3 resolved
- `count_open_questions/1`: create N open questions, verify count matches
- `prune_stale_questions/2`: create old questions with times_asked=1, verify pruned; create old with times_asked=3, verify kept

**Phase 5 tests** — new `apps/lincoln/test/lincoln/events/opportunity_detector_test.exs`
- Thought failure rate detection: emit 25 thought_failed + 5 thought_completed events, verify opportunity enqueued
- Queue cap: pre-fill 5 pending opportunities, verify scan returns :queue_full
- Rate limiting: create a committed code change 10 minutes ago, verify `attempt/3` returns :rate_limited
- File safety: verify `safe_to_modify?/1` rejects `lib/lincoln/autonomy/evolution.ex`, accepts `lib/lincoln/substrate/foo.ex`

### Dashboard Integration

**Memory distribution display** — `apps/lincoln/lib/lincoln_web/live/dashboard_live.ex`
- Add `Memory.type_distribution(agent)` to `calculate_stats/1`
- Display as percentage breakdown or small bar in stats grid

**Self-improvement dashboard section** — `apps/lincoln/lib/lincoln_web/live/substrate_live.ex`
- Query `ImprovementQueue.status(agent)` — show pending/in-progress/completed/failed counts
- Show most recent improvement opportunity (pattern, status)
- Show most recent code change (file_path, description, outcome)
- Subscribe to PubSub for real-time updates

### End-to-End Verification

1. Start substrate: `Lincoln.Substrate.start_agent/1`
2. Seed 10+ similar beliefs with varying confidence/entrenchment
3. Run 100+ ticks and verify:
   - Duplicates consolidated (belief count decreases)
   - Focus history shows diverse belief IDs (DiversityMonitor logs)
   - Memory type distribution more balanced (`type_distribution/1`)
4. Seed 20+ investigation questions, verify batch drain activates
5. Manually enqueue an improvement opportunity, verify self-improvement impulse fires

---

## File Reference

| File | Status | What changed |
|------|--------|-------------|
| `apps/lincoln/lib/lincoln/beliefs.ex` | Modified | Creation-time dedup, lower thresholds, multi-factor winner, metrics |
| `apps/lincoln/lib/lincoln/substrate/diversity_monitor.ex` | Rewritten | Shannon entropy, graduated response, belief suppression |
| `apps/lincoln/lib/lincoln/substrate/attention.ex` | Modified | entrenchment_dampening, suppressed_belief_ids, settled_penalty fix |
| `apps/lincoln/lib/lincoln/substrate/attention_params.ex` | Modified | New default fields in all presets |
| `apps/lincoln/lib/lincoln/memory.ex` | Modified | Importance rebalanced, type-diverse retrieval, type_distribution |
| `apps/lincoln/lib/lincoln/substrate/thought.ex` | Modified | Reflection rate limiting, batch investigation dispatch |
| `apps/lincoln/lib/lincoln/substrate/investigation_thought.ex` | Modified | execute_batch/2 |
| `apps/lincoln/lib/lincoln/substrate/cognitive_impulse.ex` | Modified | Dynamic investigation cooldown |
| `apps/lincoln/lib/lincoln/questions.ex` | Modified | count_open_questions, prune_stale_questions, ordering |
| `apps/lincoln/lib/lincoln/substrate/substrate.ex` | Modified | Question pruning + opportunity detection intervals |
| `apps/lincoln/lib/lincoln/autonomy/self_improvement.ex` | Modified | Safety guardrails (rate limit, file safety, forbidden list) |
| `apps/lincoln/lib/lincoln/autonomy.ex` | Modified | most_recent_code_change/2 |
| `apps/lincoln/lib/lincoln/events/opportunity_detector.ex` | **NEW** | Automatic improvement opportunity detection |
| `apps/lincoln/lib/lincoln/autonomy/evolution.ex` | TODO | rollback_change/1 |
