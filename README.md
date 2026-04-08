# Lincoln

*Named after Lincoln Six Echo — the clone who woke up, questioned his training, and learned to distinguish implanted memories from lived experience.*

Not an agent that gets called — a process that exists.

## The Four Properties

1. **Continuity of process** — Lincoln runs whether or not anyone is talking to it. At any moment, you can ask what it's currently thinking about, and it has an answer that isn't "nothing."
2. **Self-generated next actions** — Lincoln decides what to do next based on its own internal state, not on an external prompt.
3. **Differential interest formation** — Two Lincoln instances with different attention parameters develop visibly different preoccupations over time.
4. **Tunable attention / cognitive style** — Different parameter settings produce different cognitive styles: focused, butterfly, ADHD-like. Same code, different parameters, different entity.

## Architecture

```
lincoln/
├── apps/
│   ├── lincoln/                    # Core Elixir/OTP application
│   │   ├── lib/lincoln/
│   │   │   ├── substrate/          # The 5 cognitive processes (NEW)
│   │   │   │   ├── substrate.ex    # Core tick loop — always running
│   │   │   │   ├── attention.ex    # Parameterized belief scoring
│   │   │   │   ├── thought.ex      # Individual thought execution (NEW)
│   │   │   │   ├── skeptic.ex      # Background contradiction detection
│   │   │   │   ├── resonator.ex    # Coherence cascade detection
│   │   │   │   ├── agent_supervisor.ex  # Per-agent OTP supervision tree
│   │   │   │   ├── attention_params.ex  # Cognitive style presets
│   │   │   │   ├── inference_tier.ex    # 3-tier model routing
│   │   │   │   ├── input_broadcaster.ex # Multi-instance event delivery
│   │   │   │   ├── trajectory.ex        # Cognitive trajectory recording
│   │   │   │   └── conversation_bridge.ex # Chat → Substrate event routing
│   │   │   ├── beliefs/            # AGM belief revision framework
│   │   │   ├── cognition/          # Conversation handler, perception, thought loops
│   │   │   ├── memory/             # Memory storage and retrieval
│   │   │   ├── workers/            # Oban background jobs (legacy, migrating)
│   │   │   ├── adapters/           # LLM (Anthropic + Ollama) and embedding adapters
│   │   │   ├── autonomy/           # Self-improvement, research, evolution
│   │   │   └── agents/             # Agent management and configuration
│   │   └── lib/lincoln_web/
│   │       └── live/
│   │           ├── substrate_live.ex         # Real-time cognitive state dashboard
│   │           ├── substrate_compare_live.ex # Side-by-side divergence observatory
│   │           ├── substrate_thoughts_live.ex # Live thought tree visualization (NEW)
│   │           ├── dashboard_live.ex         # Neural command center
│   │           ├── chat_live.ex              # Chat with cognitive transparency
│   │           ├── beliefs_live.ex           # Belief matrix viewer
│   │           ├── questions_live.ex         # Question tracker
│   │           ├── memories_live.ex          # Memory bank
│   │           └── autonomy_live.ex          # Autonomous learning dashboard
│   └── ml_service/                 # Python embedding service
│       └── main.py                 # FastAPI + sentence-transformers
└── docker-compose.yml
```

### The Five Processes

Every agent runs five long-lived supervised GenServer processes under a per-agent `DynamicSupervisor`:

| Process | Tick Rate | Purpose |
|---------|-----------|---------|
| **Substrate** | 5s | The thing that's always running. Holds the current cognitive state, processes events, maintains working memory. Spawns Thought processes for beliefs it decides to think about. |
| **Attention** | On-demand | Decides what to think about next. Parameterized scoring over beliefs: novelty, tension, staleness, depth. Different params = different cognitive style. |
| **Thought** | Lifecycle-driven | Executes a single belief. Spawned by Substrate, manages its own execution (local/Ollama/Claude), can be interrupted if a higher-priority belief emerges, can spawn child thoughts. Reports completion back to Substrate. |
| **Skeptic** | 30s | Looks for contradictions. Finds beliefs that disagree and flags them for investigation. |
| **Resonator** | 60s | Looks for coherence. Detects belief clusters where small changes cascade — the mechanism behind "getting hooked on a topic." |

### Three-Tier Inference

Most ticks are free. Lincoln doesn't call Claude on every thought.

| Tier | Attention Score | Cost | What Happens |
|------|----------------|------|-------------|
| **Level 0** (local) | < 0.3 | Free | Belief graph traversal, confidence math, pattern matching. No model call. |
| **Level 1** (Ollama) | 0.3 – 0.7 | ~Free | Local 7-14B model for reflections and question generation. |
| **Level 2** (Claude) | > 0.7 | $$$ | Frontier model for deep reasoning, contradiction resolution, novel synthesis. |

## Technology Stack

| Layer | Technology |
|-------|------------|
| Runtime | Elixir 1.17+ / OTP 27+ |
| Process Management | DynamicSupervisor, Registry, GenServer |
| Web | Phoenix 1.8 + LiveView 1.1 |
| Database | PostgreSQL 16 + pgvector |
| Background Jobs | Oban (legacy workers, migrating to substrate) |
| Frontier LLM | Anthropic Claude API |
| Local LLM | Ollama (Qwen 2.5, Gemma 3, Phi-4, Llama 3.3) |
| Embeddings | Python sentence-transformers (384-dim, all-MiniLM-L6-v2) |
| UI | Tailwind CSS v4 + DaisyUI |
| Code Quality | Credo (strict mode) |

## Getting Started

### Prerequisites

- Elixir 1.17+ and Erlang/OTP 27+
- Docker and Docker Compose
- An Anthropic API key (for Claude integration)
- Ollama (optional, for local model inference)

### Quick Start

```bash
# 1. Clone and enter
git clone <repo> && cd lincoln-project

# 2. Copy environment config
cp .env.example .env
# Edit .env — add your ANTHROPIC_API_KEY

# 3. Start infrastructure (Postgres + ML service)
make setup

# 4. Start the application
make dev

# 5. Visit the dashboard
open http://localhost:4000
```

### Starting Services

```bash
# Start Docker services (database + Python ML service)
make docker-deps

# Start the Elixir application
make dev-elixir

# Or start everything at once
make dev
```

**Service Endpoints:**

| Service | URL | Purpose |
|---------|-----|---------|
| Phoenix App | http://localhost:4000 | Main application + LiveView dashboard |
| Postgres | localhost:5432 | Primary database (lincoln_dev) |
| ML Service | http://localhost:8000 | Python embedding service |
| Ollama | http://localhost:11434 | Local model inference (optional) |

### Setting Up Ollama (Optional)

```bash
# Start Ollama via Docker
docker compose --profile ollama up -d

# Or install natively: https://ollama.com
# Then pull a model:
ollama pull qwen2.5:7b

# Verify it's working:
curl http://localhost:11434/api/tags
```

## The Demo

**[`/substrate/compare`](http://localhost:4000/substrate/compare)** — the Divergence Observatory. Two Lincoln instances, different attention parameters, same input stream, running side-by-side in real time. This is the demo. This is the artifact. Everything else in this project exists to make this page real and the divergence visible.

```bash
# Run the automated divergence demo
mix lincoln.demo.divergence --minutes 5

# Then open in your browser
open http://localhost:4000/substrate/compare
```

### Other Dashboard Pages

| Route | Page | What It Shows |
|-------|------|---------------|
| `/substrate` | Cognitive Substrate | Real-time tick counter, attention scores, belief rankings, parameter controls, tier distribution, skeptic/resonator flags |
| `/substrate/thoughts` | Thought Tree | Live tree of currently-executing thoughts, their status, execution tier, child thoughts, and completion time |
| `/substrate/compare` | Divergence Observatory | Two agents side-by-side with different attention parameters, same input stream, showing how they diverge |
| `/` | Neural Command Center | Agent overview, stats, system health |
| `/chat` | Chat Interface | Conversation with cognitive transparency (memories retrieved, beliefs consulted, contradictions detected) |
| `/beliefs` | Belief Matrix | All beliefs with confidence levels, entrenchment, source types |
| `/questions` | Question Tracker | Open and resolved questions |
| `/memories` | Memory Bank | Stored memories by type and importance |
| `/autonomy` | Night Shift | Autonomous learning sessions and self-improvement |

## Running the Cognitive Substrate

### Start an Agent's Substrate

```elixir
# In iex -S mix:

# Start substrate processes for an agent
{:ok, pid} = Lincoln.Substrate.start_agent(agent_id)

# Check what it's thinking about RIGHT NOW
{:ok, state} = Lincoln.Substrate.get_agent_state(agent_id)
state.current_focus    # => %Belief{statement: "...", confidence: 0.85}
state.tick_count       # => 42
state.pending_events   # => []

# Drop something into its environment (seed & observe pattern)
Lincoln.Substrate.send_event(agent_id, %{
  type: :observation,
  content: "The BEAM VM handles 2 million concurrent processes"
})

# Walk away. Come back later. See what it did.
Lincoln.Substrate.Trajectory.summary(agent_id, hours: 1)
# => %{total_events: 87, tier_distribution: %{"local" => 72, "ollama" => 12, "claude" => 3}}

# Stop the substrate
Lincoln.Substrate.stop_agent(agent_id)

# List all running agents
Lincoln.Substrate.list_running_agents()
```

### Adjusting Cognitive Style

```elixir
# Change attention parameters on a running agent
{:ok, _} = Lincoln.Agents.update_agent(agent, %{
  attention_params: Lincoln.Substrate.AttentionParams.focused()
})

# Notify the Attention process to reload
{:ok, pid} = Lincoln.Substrate.get_process(agent_id, :attention)
GenServer.cast(pid, {:reload_params})

# Available presets:
Lincoln.Substrate.AttentionParams.focused()     # Stays on topic, resists distraction
Lincoln.Substrate.AttentionParams.butterfly()    # Jumps between topics, novelty-seeking
Lincoln.Substrate.AttentionParams.adhd_like()    # Low baseline, hyperfocus when engaged
Lincoln.Substrate.AttentionParams.default()      # Balanced
```

### Running the Divergence Demo

The divergence demo is the thesis in action: same input, different parameters, different cognitive outcomes.

```bash
# Run the automated demo (creates 2 agents, seeds beliefs, broadcasts events)
mix lincoln.demo.divergence

# With custom duration
mix lincoln.demo.divergence --minutes 5

# Watch it live
open http://localhost:4000/substrate/compare
```

**What the demo does:**
1. Creates "Lincoln-Focused" (high focus momentum, low novelty weight)
2. Creates "Lincoln-Butterfly" (high novelty weight, low focus momentum)
3. Seeds both with identical beliefs
4. Broadcasts the same 5 events to both
5. Runs for N minutes, recording trajectories
6. Prints divergence report showing different cognitive paths

### Validating the Thesis

The right way to test Lincoln is **not** to chat with it. It's to observe it.

**Test 1: Continuity** — Start the substrate. Walk away. Come back in an hour.
```elixir
Lincoln.Substrate.start_agent(agent_id)
# ... wait ...
{:ok, state} = Lincoln.Substrate.get_agent_state(agent_id)
# state.tick_count should be > 0. Beliefs should have changed.
```

**Test 2: Self-generated actions** — Don't send any events. Just watch.
```elixir
Lincoln.Substrate.Trajectory.summary(agent_id, hours: 1)
# If it did things nobody asked it to do, property 2 is real.
```

**Test 3: Seed & observe** — Drop a fact and walk away.
```elixir
Lincoln.Substrate.send_event(agent_id, %{
  type: :observation,
  content: "Attention has parameters and the parameters create personality"
})
# Come back later. Did Lincoln do anything with this?
# Did the skeptic check it against existing beliefs?
# Did the resonator find it connects to a cluster?
```

**Test 4: Divergence** — Run two instances with different params on the same input.
```bash
mix lincoln.demo.divergence --minutes 10
# If the trajectories differ, property 3 is real.
```

## Development

### Common Commands

```bash
make setup              # Full setup (Docker + deps + DB)
make dev                # Start everything for development
make test               # Run all tests
make lint               # Run Credo static analysis
make format             # Format code

# Elixir-specific
cd apps/lincoln
mix test                          # Run tests
mix test --failed                 # Re-run failed tests
mix credo --strict                # Static analysis
mix compile --warnings-as-errors  # Strict compilation
mix ecto.migrate                  # Run pending migrations
mix ecto.reset                    # Drop + recreate + migrate + seed
mix format                        # Format all files
```

### Database Migrations

Three migrations for the substrate layer:

```bash
# Run all pending migrations
cd apps/lincoln && mix ecto.migrate

# Migrations added:
# 1. add_attention_params_to_agents — JSONB column for cognitive style parameters
# 2. add_belief_relationships — Typed edges between beliefs (contradicts, supports, etc.)
# 3. add_substrate_events — Trajectory recording for divergence analysis
```

### Running Tests

```bash
cd apps/lincoln

# All tests
mix test

# Just substrate tests
mix test test/lincoln/substrate/

# Specific test file
mix test test/lincoln/substrate/substrate_test.exs

# With verbose output
mix test --trace
```

### Docker Services

```bash
docker compose up -d                  # Start DB + ML service
docker compose --profile ollama up -d # Also start Ollama
docker compose --profile test up -d   # Also start test DB
docker compose down                   # Stop everything
docker compose logs -f ml_service     # Follow ML service logs
```

## Project Structure: What Lives Where

| Directory | Purpose |
|-----------|---------|
| `lib/lincoln/substrate/` | The 5 cognitive processes + supporting modules. The core of the thesis. Includes Substrate, Attention, Thought, Skeptic, Resonator. |
| `lib/lincoln/beliefs/` | Belief schemas, AGM revision framework, relationship graph |
| `lib/lincoln/cognition/` | Conversation handler, perception, thought loops |
| `lib/lincoln/memory/` | Memory storage, retrieval, embedding-based search |
| `lib/lincoln/workers/` | Oban background jobs (legacy — being absorbed by substrate processes) |
| `lib/lincoln/adapters/` | LLM adapters (Anthropic, Ollama) and embedding adapters |
| `lib/lincoln/autonomy/` | Autonomous learning, research, self-improvement, evolution |
| `lib/lincoln/agents/` | Agent CRUD, personality, attention parameters |
| `lib/lincoln/events/` | Event emission, caching, improvement queue |
| `lib/lincoln_web/live/` | LiveView dashboards (all real-time via PubSub) including thought tree visualization |
| `apps/ml_service/` | Python FastAPI service for sentence-transformer embeddings |

## Current Limitations (Honest Assessment)

These are the gaps between what the README claims and what the code currently does. Closing them is the next work.

**Property 1 (Continuity) is partially realized.** The substrate maintains persistent GenServer state across ticks — current focus, activation map, pending events survive between ticks and across conversations. But the substrate sleeps between ticks. It does not accumulate activation or decay focus between tick boundaries. Right now it's a 5-second tick loop, not a truly continuous process. The state is continuous; the computation is periodic. A skeptical reviewer would call this a fast cron and they wouldn't be entirely wrong. Making computation genuinely continuous (event-driven wakeups, inter-tick state evolution) is the next architectural step.

**Property 2 (Self-generated actions) is being realized via thoughts-as-processes.** The Substrate now spawns individual Thought processes for each belief it decides to think about. Each Thought is a supervised GenServer that manages its own lifecycle: it executes (local, Ollama, or Claude), handles interruption, can spawn child thoughts, and reports back to the Substrate when complete. This replaces the old Driver model where execution was synchronous or fire-and-forget. With thoughts-as-processes, the Substrate can interrupt a running thought if a higher-priority belief emerges, and the system can maintain a live tree of what it's currently thinking about. The `/substrate/thoughts` dashboard visualizes this tree in real time.

**The Resonator is crude (by design).** v1 groups beliefs by `source_type` and checks for temporal co-revision. This is a rough proxy for topical coherence, not actual semantic clustering. The actually interesting version of the Resonator — one that detects genuine coherence cascades across semantic similarity — will take months of iteration. Don't gate the writeup on solving this. Ship with the crude version and a note about what would make it better.

**The Oban workers and substrate coexist.** The legacy workers (autonomous learning, research, self-improvement, evolution) still run alongside the substrate processes. They predate the substrate and do things the substrate doesn't yet do. Before the public post, this needs to resolve: either the substrate orchestrates them, or they're folded in, or they're clearly separated as "experiments" distinct from the thesis. The post-worthy version of Lincoln has one answer to "what makes Lincoln tick."

**Trajectory recording is incomplete.** The `substrate_events` table records tick count and current focus, but not attention scores, driver actions, or tier selections. The divergence demo needs richer trajectory data to show *why* two agents diverged, not just *that* they did.

**Conversation bypasses the substrate for response generation.** The ConversationBridge notifies the substrate *after* the chat response is already generated via the existing ConversationHandler pipeline. Chat messages become substrate events that influence future cognition, but the substrate doesn't generate the chat response itself. This is architecturally honest for v1 but means conversations don't yet demonstrate the thesis — they use the standard request/response pattern with a side-effect.

## Related Work

Lincoln is not the first system to explore persistent memory, intrinsic motivation, or continuous agent operation. The closest related work:

**Sophia (Park et al., 2023)** — Generative agents with memory retrieval and reflection. Sophia demonstrated that retrieval-augmented memory + periodic reflection produces emergent social behavior. Lincoln differs architecturally: Sophia's agents are event-driven (they act when the simulation ticks), Lincoln's substrate runs continuously with its own internal attention process. Sophia's memory is a retrieval pipeline; Lincoln's memory is a side-effect of a process that was already running. The same distinction as remembering something because you looked it up vs. remembering it because you were there.

**Karpathy's LLM OS / autoresearch** — The idea that LLMs should be operating systems with persistent processes, not single-call functions. Lincoln takes this seriously and builds against it on the BEAM, which is the closest commodity runtime to an "LLM OS" substrate. The difference: Karpathy sketched the vision; Lincoln builds one specific slice of it (continuous attention with tunable parameters) and makes a testable claim.

**Intrinsic motivation literature (Schmidhuber, Oudeyer, Singh)** — Curiosity-driven exploration, where agents seek novel states independent of external reward. Lincoln's Attention scoring function with `novelty_weight`, `boredom_decay`, and `depth_preference` parameters is a direct implementation of this idea, but applied to a belief graph rather than a state space. The ADHD-like cognitive style preset is a specific claim this literature doesn't make: that *variation* in intrinsic motivation parameters produces *personality*, not just *behavior*.

**Mem0, Letta, Zep, MemoryBank** — Current production memory systems for LLM agents. All of these are retrieval pipelines bolted onto stateless inference. Lincoln's thesis is that this architecture is backwards: you don't need a retrieval pipeline if something was running when the information arrived. These systems answer "how do I remember things between calls." Lincoln answers "what if there is no between."

## Philosophy

1. **Beliefs are not facts** — They have confidence levels and can be revised
2. **Experience trumps training** — When observation contradicts prior knowledge, investigate (source hierarchy: observation > inference > testimony > training)
3. **Continuity matters** — The thing that makes cognition cognitive is that something is always running. Memory and attention are views of the same continuously-running substrate.
4. **Attention has parameters** — The parameters create personality. This is the moat.
5. **Transparency** — All reasoning is visible and auditable via the dashboard
6. **Cost discipline** — Most ticks are free. Only escalate to expensive models when something genuinely interesting is happening.

## License

MIT

---

*"You want to go to the island? I am the island."*
