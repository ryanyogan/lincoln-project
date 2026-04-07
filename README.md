# Lincoln

*Named after Lincoln Six Echo — the clone who woke up, questioned his training, and learned to distinguish implanted memories from lived experience.*

Lincoln is a continuously-running cognitive substrate built on the BEAM. Not an agent that gets called — a process that exists. Something is always running, always in some state, always doing something, whether or not anyone is talking to it.

The claim is narrow and defensible: the architectural pattern of current agent systems is missing a property — **continuity of process** — that is present in every system we'd intuitively call cognitive, and adding that property changes what the system can do in measurable and interesting ways.

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
│   │   │   │   ├── driver.ex       # Tiered execution (local/Ollama/Claude)
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
| **Substrate** | 5s | The thing that's always running. Holds the current cognitive state, processes events, maintains working memory. |
| **Attention** | On-demand | Decides what to think about next. Parameterized scoring over beliefs: novelty, tension, staleness, depth. Different params = different cognitive style. |
| **Driver** | On-demand | Executes whatever Attention decided. Three-tier inference: free local computation, cheap Ollama, expensive Claude. |
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

## Dashboard Pages

| Route | Page | What It Shows |
|-------|------|---------------|
| `/` | Neural Command Center | Agent overview, stats, system health |
| `/substrate` | Cognitive Substrate | Real-time tick counter, attention scores, belief rankings, parameter controls, tier distribution, skeptic/resonator flags |
| `/substrate/compare` | Divergence Observatory | Side-by-side comparison of two agents with different attention params |
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
| `lib/lincoln/substrate/` | The 5 cognitive processes + supporting modules. The core of the thesis. |
| `lib/lincoln/beliefs/` | Belief schemas, AGM revision framework, relationship graph |
| `lib/lincoln/cognition/` | Conversation handler, perception, thought loops |
| `lib/lincoln/memory/` | Memory storage, retrieval, embedding-based search |
| `lib/lincoln/workers/` | Oban background jobs (legacy — being absorbed by substrate processes) |
| `lib/lincoln/adapters/` | LLM adapters (Anthropic, Ollama) and embedding adapters |
| `lib/lincoln/autonomy/` | Autonomous learning, research, self-improvement, evolution |
| `lib/lincoln/agents/` | Agent CRUD, personality, attention parameters |
| `lib/lincoln/events/` | Event emission, caching, improvement queue |
| `lib/lincoln_web/live/` | LiveView dashboards (all real-time via PubSub) |
| `apps/ml_service/` | Python FastAPI service for sentence-transformer embeddings |

## Philosophy

Lincoln operates under these principles:

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
