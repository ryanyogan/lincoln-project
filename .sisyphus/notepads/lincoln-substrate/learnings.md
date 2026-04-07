
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
