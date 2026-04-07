
## Attention GenServer (Task 11)

- `list_beliefs/2` needed `order_by` option added — was hardcoded to `desc: confidence`. Added dynamic `order_by` support with keyword list passthrough to `Ecto.Query.order_by/3`.
- Attention uses offset-based round-robin: `belief_offset` tracks position, wraps to 0 when past end.
- `handle_call(:next_thought)` does a two-phase check: try current offset, if nil reset to 0 and retry. This avoids redundant state by letting the wrap-around happen naturally.
- Registry naming: `{agent_id, :attention}` — follows same pattern as `:substrate`.
- No tick loop in Attention — it's reactive, called by Substrate/Driver.
- Score is flat 0.5 placeholder — real scoring comes in Step 2 (Task 12).

## ConversationBridge (Task - conversation routing)

- Call site: `ChatLive.handle_info({:process_message, content}, socket)` — the async handler triggered by `send(self(), {:process_message, content})` from `handle_event("send_message", ...)`.
- `ConversationHandler.process_message/3` returns `{:ok, cognitive_result}` where `cognitive_result` has `.response` (string) and `.cognitive_metadata` (map with `:memories_retrieved`, `:beliefs_consulted`, etc.).
- Bridge call placed at top of success branch, before `add_assistant_message` — fire-and-forget, returns `:ok` regardless of Substrate state.
- `Substrate.send_event/2` requires `agent_id` to be binary (UUID string) — `agent.id` from socket assigns satisfies this.
- Zero modifications to `conversation_handler.ex` — bridge lives entirely in the LiveView layer.

## AttentionParams Module (Task - attention schema)

- Migration: `20260407193358_add_attention_params_to_agents.exs` — uses `:map` type (maps to JSONB in PostgreSQL).
- Agent schema: `attention_params` field added after `personality`, default `%{}`, included in changeset cast.
- Module: `Lincoln.Substrate.AttentionParams` with 4 presets: `focused()`, `butterfly()`, `adhd_like()`, `default()`.
- Validation: `validate/1` checks 6 required params — 5 floats (0.0-1.0) + 1 integer (1000-60000 ms).
- Merge: `merge/1` overlays custom params on default preset.
- All presets tested and validated successfully.

## InferenceTier Module (Task 9)

- Pure function module (no GenServer) — selects inference tier based on attention score.
- Three tiers: `:local` (no model), `:ollama` (cheap local), `:claude` (expensive frontier).
- `select_tier(score, opts)` — thresholds: 0.3 (ollama), 0.7 (claude). Configurable via opts.
- Budget override: `:minimal` budget forces `:local` regardless of score.
- `execute_at_tier(tier, messages, opts)` — returns `{:ok, :skipped}` for local, delegates to adapters for others.
- Fallback: `:ollama` failure with `:ollama_unavailable` → tries `:claude`.
- Adapters injected via `Application.get_env/3` — allows testing without Ollama module existing yet.
- All 8 tests pass; compile clean with `--warnings-as-errors`.

## Ollama LLM Adapter (Task 10)

- Separate file `adapters/llm/ollama.ex` — follows AGENTS.md rule against nesting modules in same file (unlike existing Anthropic/Mock in `llm.ex`).
- `chat/2` returns `{:ok, content_string}` matching behaviour's `{:ok, String.t()}` type — not a map wrapper.
- Ollama API: `POST /api/chat` with `stream: false` — response at `body["message"]["content"]`.
- Connection errors: `%{reason: :econnrefused}` pattern matches Req/Mint transport error structs via map matching on structs.
- `health_check/0` uses `GET /api/tags` — lightweight endpoint that lists models.
- Config via `Application.get_env(:lincoln, :ollama, [])` — separate from `:llm` config.
- Docker: `ollama` profile — optional, not started by default `docker compose up`.
- `extract/3` reuses Anthropic's JSON extraction pattern: try `Jason.decode` first, fall back to regex extraction.

## Parameterized Belief Scoring (Task 12 — replacing round-robin)

- Replaced `belief_offset` round-robin with 4-component scoring: novelty, tension, staleness, depth.
- State changes: removed `belief_offset`, added `attention_params`, `current_focus_id`, `activation_map`.
- `activation_map` tracks when each belief was last returned by `next_thought` — drives staleness scoring.
- Scoring formula: `novelty_weight * novelty + (1-novelty_weight) * depth * depth_preference + tension * (1-focus_momentum) + staleness * boredom_decay`, capped at [0.0, 1.0].
- Focus momentum: current_focus_id belief gets `focus_momentum * 0.3` bonus — with default params (0.5), that's 0.15 boost.
- Key gotcha: focus_momentum boost (0.15) beats boredom_decay (0.1) with default params, so identical beliefs don't rotate. Tests for rotation need `focus_momentum: 0.0, boredom_decay: 0.5`.
- `score_breakdown/2` public API returns `%{novelty, tension, staleness, depth, total}` for debugging.
- `handle_cast({:reload_params})` reloads from DB — no restart needed when params change.
- `get_attention_params/1` handles both string and atom keys from DB (JSONB returns string keys).
- `recency_novelty`: 1.0 within 24h, linear decay to 0.0 over 7 days. `challenged_recently`: 1.0 within 1h, decay over 24h.
- `DateTime.diff/3` with `:second` for all time comparisons — avoids integer division issues.

## Driver Tiered Inference (Task 14)

- Driver accepts both `{belief, score}` tuples and plain belief maps — backwards compatible with pre-Attention callers.
- Async pattern: `Task.async/1` in GenServer, results arrive via `handle_info({ref, result})`. Must `Process.demonitor(ref, [:flush])` to prevent stale DOWN messages.
- `pending_tasks` map stores `%{task_ref => tier_atom}` — needed to know which tier completed when result arrives.
- Memory creation uses `Lincoln.Memory.create_memory/2` (not `record_memory`) — takes `(%Agent{}, attrs_map)`.
- Memory write is fire-and-forget via `Task.start/1` — Driver doesn't block on DB.
- `Float.round(score / 1, 2)` trick: forces integer scores through float division so `Float.round/2` doesn't crash on integer input.
- Token budget integration deferred — defaults to `:full`. Will need session context plumbing from AgentSupervisor.

## Dashboard Attention Controls (Task 15)

- `<.input>` component wraps each field in `<div class="fieldset mb-2"><label>` — passing `class` overrides only the `<input>` element class, the wrapper stays.
- `to_form/2` with `as: :attention_params` — form params arrive in `handle_event` as `%{"attention_params" => %{...}}` with string keys.
- Agent `attention_params` from DB may have string or atom keys (JSONB → strings). `build_params_form/1` checks both: `params["key"] || params[:key] || default`.
- Dynamic Tailwind classes like `"text-#{@color}"` won't be compiled — must use explicit class functions that return full string literals.
- Tier tracking piggybacks on existing `:executed` handler — pattern matches `%{tier: tier}` from action map, no new PubSub subscription needed.
- `update_top_beliefs/3` deduplicates by `belief.id` before sorting — prevents same belief appearing multiple times in the top-5 list.

## 2026-04-07: Belief Relationships Implementation

### Created
- Migration: `20260407195716_add_belief_relationships.exs`
  - Table: `belief_relationships` with binary_id primary key
  - Fields: agent_id, source_belief_id, target_belief_id, relationship_type, confidence, detected_by, evidence
  - Indexes on agent_id, source_belief_id, target_belief_id
  - Unique constraint on (source_belief_id, target_belief_id, relationship_type)

- Schema: `Lincoln.Beliefs.BeliefRelationship`
  - Relationship types: contradicts, supports, refines, depends_on, related
  - Detected by: skeptic, resonator, manual, inference
  - Confidence: 0.0-1.0 float
  - Belongs to: agent, source_belief, target_belief

- Context functions in `Lincoln.Beliefs`:
  - `create_relationship/1` - Create new relationship
  - `find_relationships/2` - Find all relationships for a belief (incoming + outgoing)
  - `find_contradictions/1` - Find all contradictions for an agent
  - `find_support_cluster/2` - Find beliefs connected by "supports" relationships
  - `relationship_exists?/4` - Check if relationship already exists

- Updated `Lincoln.Beliefs.Belief` schema:
  - Added `has_many :outgoing_relationships` (source_belief_id)
  - Added `has_many :incoming_relationships` (target_belief_id)

### Design Notes
- Relationships are directional (source → target)
- Unique constraint prevents duplicate relationships of same type between same beliefs
- Preloading beliefs in find_contradictions and find_support_cluster for efficient querying
- Follows existing pattern from BeliefRevision associations

## Skeptic GenServer

- `find_similar_beliefs/3` returns plain maps with atom keys (raw SQL), not `%Belief{}` structs. Dot access works on maps but they lack struct guarantees.
- `Pgvector.Ecto.Vector` loads as `%Pgvector{}` struct. Can pass directly to `Repo.query!` — the `Pgvector.Extensions.Vector` Postgrex extension handles encoding.
- `relationship_exists?/4` only checks one direction (source→target). Skeptic checks both directions to avoid duplicate contradictions when beliefs are investigated in opposite order on later ticks.
- Beliefs without embeddings are silently skipped (no crash) — `get_embedding/1` returns nil, caller pattern-matches on it.

## Resonator GenServer (Coherence Cascade Detection)

- Follows Skeptic pattern exactly: GenServer with tick, Registry naming `{agent_id, :resonator}`, `child_spec/1`, `defstruct`.
- Tick interval 60s (slower than Skeptic's 30s) — cascades are macro patterns, don't need frequent checks.
- v1 clustering is trivially simple: `Enum.group_by(& &1.source_type)` — groups beliefs by source type, checks each group for cascade conditions.
- Cascade condition: 3+ beliefs in same source_type cluster that were all updated within the last hour (`@cascade_window_hours * 3600` seconds).
- `cascade_active?/1` uses `DateTime.diff(now, belief.updated_at, :second)` — consistent with Attention's time math patterns.
- `process_cascade/2` creates "supports" relationships between all pairs: `for a <- cluster, b <- cluster, a.id < b.id` — UUID string comparison for dedup ordering.
- `relationship_exists?/4` only checks one direction (source→target), but since pair generation enforces `a.id < b.id`, each pair is only processed once.
- `broadcast_resonator_flag/2` already existed in PubSubBroadcaster — was pre-built alongside `broadcast_skeptic_flag/2`.
- Cascade score = `cluster_size * avg_confidence` — simple product, useful for Attention weighting later.
- Test for relationship deduplication: run two ticks, assert same count. 3 beliefs = 3 pairs = 3 "supports" relationships, each belief involved in 2.

## 2026-04-07: Extended AgentSupervisor to 5 Processes

**Task**: Add Skeptic and Resonator to per-agent AgentSupervisor.

**Changes**:
1. **AgentSupervisor.init/1**: Added Skeptic (30s tick) and Resonator (60s tick) to children list
   - Skeptic: `%{agent_id: agent_id, tick_interval: 30_000}`
   - Resonator: `%{agent_id: agent_id, tick_interval: 60_000}`
   - Updated aliases to include both new modules
   - Updated @moduledoc to reflect 5 processes

2. **Lincoln.Substrate.get_process/2**: Extended guard clause to accept `:skeptic` and `:resonator`
   - Now supports all 5 process types: `:substrate`, `:attention`, `:driver`, `:skeptic`, `:resonator`
   - Updated @doc to reflect new types

3. **Lincoln.Substrate @moduledoc**: Updated to document all 5 processes

**Verification**:
- `mix compile --warnings-as-errors` passes ✓
- Commit: `feat(substrate): extend per-agent supervisor to 5 processes`

**Architecture Notes**:
- Supervision strategy remains `:one_for_all` (all processes restart together)
- Skeptic and Resonator register via Registry as `{agent_id, :skeptic}` and `{agent_id, :resonator}`
- No changes to public API (start_agent, stop_agent, get_agent_state remain unchanged)

## 2026-04-07: Wired Skeptic/Resonator Flags into Attention Scoring

**Task**: Add `contradiction_bonus` and `cascade_bonus` scoring components to Attention.

**Changes**:
1. **beliefs.ex**: Added `find_all_relationships/1` — bulk-loads all relationships for an agent (avoids N+1 in scoring loop)
2. **attention.ex**: `score_belief/5` now accepts pre-loaded `belief_rels`, computes two new bonuses:
   - `contradiction_bonus`: filters for "contradicts" relationships, averages their confidence, scales by `interrupt_threshold * 0.4`
   - `cascade_bonus`: filters for "supports" relationships, counts them, scales by `novelty_weight * min(count/5, 1.0) * 0.3`
3. **handle_call(:next_thought)**: Pre-loads all relationships once via `find_all_relationships/1`, passes to each `score_belief` call
4. **score_breakdown**: Now returns `contradiction_bonus` and `cascade_bonus` fields alongside existing components

**Design Decisions**:
- Empty relationship list fast-paths to 0.0 via pattern match on `[]` — no DB queries, no filtering
- `interrupt_threshold` param controls contradiction bonus magnitude (high = contradictions disrupt focus)
- `novelty_weight` param controls cascade bonus magnitude (novel regions with support clusters get attention)
- Capped at `min(1.0, max(0.0, ...))` after adding bonuses to base score
