# Handoff — Resume via MCP

This file exists so I can pick up exactly where we left off after a session restart.
Read it, then connect to Lincoln via MCP and start testing.

---

## What to do first

```bash
# 1. Start the Phoenix server (if not already running)
cd apps/lincoln && mix phx.server

# 2. The substrate needs restarting to pick up the bug fix
# Either via iex -S mix in a separate terminal:
Lincoln.Substrate.stop_agent("86585126-f1af-4bce-943e-0842946e3b35")
Lincoln.Substrate.start_agent("86585126-f1af-4bce-943e-0842946e3b35")
# Or via MCP tools (see below)
```

## The MCP Server

- **URL**: http://localhost:4000/mcp
- **Config**: `.mcp.json` at project root already points there
- **Test handshake**:
```bash
curl -s -X POST http://localhost:4000/mcp/ \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"initialize","params":{},"id":1}' | python3 -m json.tool
```

## Current Agent State

- **Agent name**: Lincoln
- **Agent ID**: `86585126-f1af-4bce-943e-0842946e3b35`
- **Beliefs seeded**: 10 beliefs about BEAM/OTP/Lincoln architecture (all with confidence 0.78–0.95)
- **Substrate**: Was running at tick ~55 but needs restart to pick up the bug fix below

## The Bug That Was Just Fixed (commit 0591be5)

**Problem**: `Lincoln.Substrate.Thought.handle_continue/2` was calling `GenServer.call(self(), {:spawn_child, ...})` — a GenServer calling itself synchronously, which deadlocks with `** (EXIT) process attempted to call itself`.

**Fix**: Extracted `do_spawn_child/3` private function. `handle_continue` now calls `spawn_exploration_children(candidates, state)` which uses `Enum.reduce` through `do_spawn_child/3` — no self-call. `handle_call({:spawn_child})` also delegates to `do_spawn_child/3`.

**Status**: Fix committed and pushed (commit `0591be5`). Server needs restart to load new bytecode.

**Verification after restart**: `get_state` via MCP should show `Self-model: X thoughts (100% success)` instead of `0% success`.

## MCP Tools Available

```
observe(content, agent_id?)     → drop observation into Lincoln's environment
get_state(agent_id?)            → current cognitive state (tick, focus, score, tier, thoughts)
list_agents()                   → see all agents + substrate status
start_substrate(agent_id?)      → start cognitive processes
stop_substrate(agent_id?)       → stop them
```

## MCP Resources Available

```
lincoln://state     → live substrate state summary (text)
lincoln://beliefs   → all active beliefs with confidence (JSON)
lincoln://thoughts  → currently running Thought OTP processes (JSON)
lincoln://memories  → recent memories (JSON)
lincoln://narrative → Lincoln's autobiography (text)
```

## What to Test After Restart

1. **start_substrate** via MCP tool → should return "Substrate started"
2. Wait 10 seconds, call **get_state** → should show `Tick: 3+`, real focus belief, attention score
3. Call **get_state** again after 30 seconds → should show `Running thoughts: 0` with 100% success rate (thoughts completing, not crashing)
4. Read `lincoln://thoughts` → should show `{"running": 0, "thoughts": []}` (all completed)
5. Read `lincoln://beliefs` → should show 10 beliefs
6. **observe** something: `"Erlang processes are the unit of concurrency, not threads"` → then check get_state after 5s to see if it influenced focus
7. After ~5 minutes: read `lincoln://memories` → should show reflection memories from completed thoughts
8. After ~16 minutes (200 ticks): read `lincoln://narrative` → Lincoln's first autobiography entry

## What's Been Built (Full Summary)

**Core substrate** (Steps 1–5 original plan):
- 5 OTP processes per agent: Substrate, Attention, Driver, Skeptic, Resonator
- ThoughtSupervisor + Thought GenServer (each thought is a supervised OTP process)
- Thought interruption via `interrupt_threshold` attention parameter
- Child thoughts (tree-of-thought as process tree) — now bug-fixed
- Per-agent DynamicSupervisor + Registry isolation

**Cognitive features**:
- Theory of Mind: `user_models` table, populated from chat via ConversationBridge
- Narrative reflections: every 200 ticks, Lincoln writes autobiography via Claude
- Self-model: updated every 50 ticks from trajectory data
- Quantitative benchmarks: `mix lincoln.benchmark.run` (contradiction detection)

**Infrastructure**:
- Three-tier inference: Level 0 (free Elixir), Level 1 (Ollama), Level 2 (Claude)
- Trajectory recording per tick: focus belief, attention score, tier
- Skeptic: finds contradictions between high-confidence beliefs via embeddings
- Resonator: detects belief cluster cascades by source_type + recency

**Dashboards**:
- `/substrate` — live cognitive state + param controls + self-model widget
- `/substrate/thoughts` — live thought tree (parent + children)
- `/substrate/compare` — two-agent divergence observatory
- `/narrative` — Lincoln's autobiography
- `/benchmarks` — accuracy tracking

**MCP server** (just built):
- HTTP JSON-RPC 2.0 at `/mcp` via Phoenix router forward
- 5 tools + 5 resources
- `.mcp.json` at project root for Claude Code auto-discovery

## Key Files

```
apps/lincoln/lib/lincoln/substrate/
  substrate.ex      ← orchestrates tick cycle (Attention → spawn_thought → trajectory)
  thought.ex        ← JUST FIXED self-call bug; child spawning now works
  attention.ex      ← parameterized belief scoring
  thought_supervisor.ex ← DynamicSupervisor for Thought processes
  thoughts.ex       ← public API: list/1, count/1, list_tree/1
  inference_tier.ex ← 3-tier routing: local/ollama/claude

apps/lincoln/lib/lincoln/mcp/
  server.ex         ← Plug.Router JSON-RPC dispatcher
  tools.ex          ← 5 tools implementation
  resources.ex      ← 5 resources implementation
  plug.ex           ← (legacy, no longer used — router.ex uses forward instead)

apps/lincoln/lib/lincoln_web/router.ex
  line 53: forward "/mcp", Lincoln.MCP.Server   ← MCP routing

LEARNINGS.md        ← honest audit of what's built and what isn't
HANDOFF.md          ← this file
writeup.md          ← the research post
```

## Code Quality

- `mix credo --strict` → **found no issues** (zero across 1700+ functions)
- `mix compile --warnings-as-errors` → clean
- All committed, all pushed to https://github.com/ryanyogan/lincoln-project

## The One Outstanding Bug

After restart, if thoughts STILL fail, check the server logs for a different error. The self-call fix changes line 138 from:
```
spawn_exploration_children(candidates)       # OLD — self-call, deadlocks
```
to:
```
new_state = spawn_exploration_children(candidates, state)  # NEW — no self-call
```
If old line 138 is still in the error trace, the server didn't restart properly. Kill with Ctrl+C Ctrl+C and re-run.

## Quick Smoke Test via MCP

After restart, run these in order:
```
1. start_substrate          → "Substrate started for Lincoln"
2. [wait 10s]
3. get_state               → Tick >= 2, Focus = a belief, score = float
4. [wait 30s]
5. get_state               → Running thoughts: 0 (they complete now)
6. observe "test"           → "Observation delivered"
7. [wait 5s]
8. get_state               → Pending events: 0 (observation processed)
```

If all 8 pass, Lincoln is working correctly.
