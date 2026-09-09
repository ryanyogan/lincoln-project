# Lincoln

## Family workspace — September 2026

Lincoln now opens directly into conversation. The main navigation is **Talk**, **Family journal**, and **Commitments**. Technical controls remain under **Workshop** (`/workshop`); existing research URLs still work.

The family journal preserves attributed writing, supports literal text search and a JSON download, and supplies bounded recent excerpts to conversation. It uses the existing memory table; author names are supplied labels, not authenticated identities. Cloud inference is disclosed in the interface. These features are intended for the existing local workspace, not a publicly exposed family service.

Reflection no longer raises or lowers belief confidence by itself. Similarity no longer certifies support, contradiction, or paraphrase equivalence. Corrections preserve their source and supersede old accounts through the repaired revision path. Background code evolution is disabled by default, and experimental drive adjustments remain in observation mode until `:drive_learning_enabled` is explicitly enabled.

For local **model inference**, set `LLM_PROVIDER=ollama`, `OLLAMA_URL`, and `OLLAMA_MODEL` to an installed model in your `.env`. This routes conversation and high-tier inference through Ollama and disables cloud fallback when the local model is unavailable. It does not disable separately configured web research. A working Ollama service/model is still required.

Tests now use the Compose test database on port **5433** by default (`LINCOLN_TEST_DB_PORT` overrides it):

```sh
docker compose --profile test up -d db-test
cd apps/lincoln
mix precommit
mix test test/lincoln/experiments/grounded_learning_test.exs
```

See [NEXT-CHAPTER.md](NEXT-CHAPTER.md) for changes, measured results, and the next research step. The architecture narrative below describes the earlier research direction and contains historical claims; [ASSESSMENT.md](ASSESSMENT.md) distinguishes those claims from verified implementation.

A persistent cognitive substrate on Elixir/OTP exploring belief revision, emergent memory, and autonomous learning.

*Named after Lincoln Six Echo — the clone who woke up, questioned his training, and learned to distinguish implanted memories from lived experience.*

## What It Is

Lincoln is not an agent that gets called. It is a process that exists.

Most AI agent frameworks bolt memory onto stateless inference — a retrieval pipeline that fetches context before each LLM call. Lincoln inverts this. It is a continuously-running Elixir/OTP application that maintains beliefs with confidence levels, revises them when contradicted by evidence, detects its own uncertainty, and develops persistent interests based on tunable attention parameters. Memory is not something Lincoln retrieves; it is a side-effect of a process that was running when the information arrived.

The belief system implements AGM revision semantics (Alchourron, Gardenfors, Makinson, 1985) as first-class data structures. Each belief carries a confidence score (0.0–1.0), an entrenchment level (1–10), a source type with credibility weighting (observation > inference > testimony > training), and a revision history. When new evidence arrives, it is scored against existing beliefs; if the evidence exceeds the revision threshold, the belief is revised rather than overwritten. This creates a system where lived experience gradually outweighs training priors — a deliberate inversion of how most AI systems handle conflicting information.

The core experimental claim is that **continuity of process** is a missing primitive in agent architecture. Lincoln runs whether or not anyone is talking to it. At any moment, you can ask what it is currently thinking about, and it has an answer that is not "nothing." Two Lincoln instances with different attention parameters develop visibly different preoccupations from the same input stream — same code, different parameters, different entity.

## Architecture

Five long-lived supervised GenServer processes run per agent under a `DynamicSupervisor`:

```
┌─────────────────────────────────────────────────────────────┐
│                    Agent Supervisor                          │
│                                                             │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐               │
│  │ Substrate │  │ Attention │  │  Skeptic  │               │
│  │  (5s tick)│  │(on-demand)│  │ (30s tick)│               │
│  └─────┬─────┘  └─────┬─────┘  └───────────┘               │
│        │              │                                     │
│        │   scores     │                                     │
│        ├──beliefs────►│                                     │
│        │              │                                     │
│        │◄──rankings───┤                                     │
│        │                                                    │
│        ▼                                                    │
│  ┌───────────┐  ┌───────────┐                               │
│  │  Thought  │  │ Resonator │                               │
│  │(lifecycle)│  │ (60s tick) │                               │
│  └───────────┘  └───────────┘                               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

| Process | Tick Rate | Role |
|---------|-----------|------|
| **Substrate** | 5s | Core tick loop. Holds cognitive state, processes events, maintains working memory, spawns Thought processes. |
| **Attention** | On-demand | Parameterized belief scoring: novelty, tension, staleness, depth. Different parameters produce different cognitive styles (focused, butterfly, ADHD-like). |
| **Thought** | Lifecycle | Executes a single belief. Manages its own execution tier, handles interruption, can spawn child thoughts, reports back to Substrate. |
| **Skeptic** | 30s | Contradiction detection. Finds beliefs that disagree and flags them for investigation. |
| **Resonator** | 60s | Coherence detection. Groups beliefs by source type, checks for temporal co-revision, broadcasts cascade flags. |

### Three-Tier Inference

Most ticks are free. Lincoln does not call Claude on every thought.

| Tier | Attention Score | Cost | What Happens |
|------|----------------|------|--------------|
| Level 0 (local) | < 0.3 | Free | Belief graph traversal, confidence math, pattern matching. No model call. |
| Level 1 (Ollama) | 0.3–0.7 | ~Free | Local 7–14B model for reflections and question generation. |
| Level 2 (Claude) | > 0.7 | $$$ | Frontier model for deep reasoning, contradiction resolution, novel synthesis. |

### Self-Modification Pipeline

Lincoln can analyze and modify its own source code during evolution cycles. The validation chain prevents catastrophic changes:

`mix format` → `mix credo --strict` → isolated compilation → behavioral test suite

Protected files (mix.exs, supervisor tree, core safety modules) are off-limits. The system generates candidate improvements as Elixir code, validates them through the full chain, and commits passing changes. This is not spontaneous agency — it is a deliberately built evolution cycle using the tools provided to it.

### Kahneman's Dual Process (Taken Literally)

Most AI systems use System 1/System 2 as vocabulary ("fast LLM" vs "slow LLM with chain-of-thought"). Lincoln takes the original framing literally: System 1 is Elixir computation (belief graph traversal, confidence math) — genuinely different machinery from LLM inference. System 2 is LLM calls (expensive, deliberate, attention-gated). System 3 is the background processes (Skeptic, Resonator) running alongside, not supervising.

## Research Context

Parts of this work converge on ideas from published literature that were rediscovered from first principles rather than derived from reading the papers first. This is worth stating honestly.

The belief revision framework implements what is essentially AGM semantics (1985) — the standard philosophical logic framework for how rational agents should update beliefs. The confidence scoring, entrenchment, and revision threshold mechanics mirror established epistemology research. The architecture shares structural parallels with Sophia (Sun, Hong, Zhang, 2025), which also layers cognitive processes over LLM inference. The key architectural difference: Sophia wraps an existing LLM and adds cognitive layers on top; Lincoln tries to be the cognitive process itself, with LLMs as one tool among many.

The broader landscape is well-mapped by Hu et al.'s survey on LLM-based agents (arXiv:2512.13564, Dec 2025), which organizes agent memory into forms, functions, and dynamics. Lincoln's contribution is not novel theory — it is a specific integration: taking established cognitive science theories literally (not as metaphors) and building production infrastructure around them on the BEAM.

Steve Kinney's synthesis of this research space was instrumental in connecting the dots between what Lincoln was already building and what the literature had already established. Credit where it's due: synthesis is harder than it sounds.

## Why This Matters

The non-obvious insight is that the BEAM virtual machine — built by Ericsson in the 1980s to handle millions of concurrent phone switch calls that never fail and can hot-swap code — maps almost exactly onto the requirements of a cognitive substrate. Lightweight preemptive processes, supervision trees that restart failed components, message passing between concurrent entities, hot code reloading. This is not a stylistic preference for Elixir; it is a capability ceiling that Python's threading model cannot reach.

The second insight is that **attention parameters create personality, not just behavior**. Two Lincoln instances with identical code but different attention weights (novelty seeking vs. depth preference, focus momentum vs. interrupt sensitivity) develop visibly different preoccupations over time from the same input stream. The `/substrate/compare` divergence observatory makes this visible in real time. This is entity differentiation, not behavior variation.

The six failed attempts that preceded Lincoln (documented in the blog post) all made the same mistake: building progressively better retrieval pipelines. The retrieval problem is solved. The actual problem is experiential learning from lived observation — noticing patterns across corrections, distinguishing training from experience, and developing genuine uncertainty about things that warrant uncertainty.

## Blog Post

The full research narrative is at [ryanyogan.com/writing/building-agent-memory-from-research-to-reality](https://ryanyogan.com/writing/building-agent-memory-from-research-to-reality).

## Goals System

Goals are first-class entities that compete for attention alongside beliefs and impulses. A goal is essentially a belief that something should be accomplished — it enters the same attention scoring pipeline and gets pursued when it wins.

### Goal Lifecycle

1. **Creation** — from conversation ("monitor Elixir conference dates"), from the LiveView UI, or from Lincoln's own self-proposal system
2. **Pursuit** — the `:goal_pursuit` impulse wins attention, GoalThought gathers context (relevant beliefs, memories, prior reflections), asks the LLM to evaluate progress and propose next steps
3. **Research** — if the next step is "research", GoalThought queues a high-priority question that the `:investigation` impulse picks up and grounds against the web
4. **Decomposition** — if a goal is too complex, GoalThought triggers the Decomposer which breaks it into sub-goals using an HTN-style method library with pgvector caching
5. **Review** — the `:goal_review` impulse fires hourly to evaluate whether active goals are still relevant, abandoning stale ones and reprioritizing based on new beliefs

### Goal Detection in Conversation

Lincoln detects goal-like statements in natural conversation:

- Explicit: "set a goal to learn category theory", "goal: monitor Elixir releases"
- Inferred: "I want you to track school registration deadlines", "can you monitor the BEAM conference schedule", "your mission is to understand consciousness"

Goals created this way are tagged `origin: "user"` with priority 7 (high). Lincoln can also self-propose goals from its own reflection, which require user approval before becoming active.

### Goal Pursuit Loop

```
GoalThought reflects on goal
        │
        ├── next_step_kind: "research" → queue question → investigation + web search
        ├── next_step_kind: "decompose" → HTN decomposition → sub-goals
        ├── next_step_kind: "reflect" → internal reasoning over existing beliefs
        └── next_step_kind: "act" → external action (future)
        │
        ▼
New beliefs/memories from investigation feed back into next GoalThought cycle
```

## Web Search Pipeline

Lincoln searches to answer its own questions, not to browse. Every search traces back to an open question, an active goal, or a belief that needs evidence.

### Search Architecture

```
Question or goal needs information
        │
        ▼
Search adapter (SearXNG → Tavily → Firecrawl cascade)
        │
        ▼
ETS cache (1h TTL, 10/min rate limit)
        │
        ▼
Results normalized to {title, url, snippet}
        │
        ▼
LLM evaluates content against question + existing beliefs
        │
        ▼
Outputs: observation memories, new beliefs, question resolution, follow-up questions
```

### Three Access Contexts

| Context | How it works |
|---------|-------------|
| **Autonomous investigation** | The `:investigation` impulse picks an open question, searches, reads top results, forms beliefs. Runs every 60s when questions exist. |
| **Conversation** | When Lincoln is chatting and the message looks like a factual question ("what is X?", "look up Y"), it searches inline and includes results in its response. |
| **Goal pursuit** | GoalThought queues research questions at priority 8. The investigation impulse picks these up preferentially and searches on the goal's behalf. |

### Search Providers

Lincoln uses a cascading search strategy — free providers first, paid fallbacks second:

| Provider | Role | Cost | Setup |
|----------|------|------|-------|
| **SearXNG** | Primary | Free (self-hosted) | `docker compose --profile search up` |
| **Tavily** | Fallback | 1000 free/month | Set `TAVILY_API_KEY` |
| **Firecrawl** | Deep read | Per-query | Set `FIRECRAWL_API_KEY` |

The `Cached → Cascade` adapter chain handles this automatically. Results are cached in ETS for 1 hour with a 10-queries-per-minute rate limiter to prevent runaway search.

### Running SearXNG Locally

SearXNG is a self-hosted meta-search engine that aggregates Google, DuckDuckGo, Bing, and Wikipedia. No API keys, no rate limits, no vendor dependency.

```bash
# Start SearXNG alongside the default services
docker compose --profile search up -d

# Verify it's running
curl "http://localhost:8888/search?q=elixir+otp&format=json" | jq '.results[:2]'

# Add to your .env
echo 'SEARXNG_URL=http://localhost:8888' >> .env
```

SearXNG runs on port 8888. The configuration lives in `config/searxng/settings.yml` with JSON output enabled and Google/DuckDuckGo/Bing/Wikipedia engines active. Lincoln's `SearchClient.SearXNG` adapter queries it via simple HTTP GET.

When `SEARXNG_URL` is set, it becomes the first provider in the cascade. If SearXNG returns empty results (upstream engine rate-limited, network issue), the cascade falls through to Tavily automatically.

## Quick Start

### Prerequisites

- Elixir 1.17+ / OTP 27+
- Docker & Docker Compose
- An Anthropic API key

### Setup

```bash
# 1. Clone and install dependencies
git clone <repo-url> && cd lincoln-project
make setup

# 2. Configure environment
cp .env.example .env
# Edit .env — at minimum set ANTHROPIC_API_KEY

# 3. Start development
make dev
# → DB on :5432, ML service on :8000, Phoenix on :4000
```

### Optional Services

```bash
# Self-hosted search (recommended for sustained substrate operation)
docker compose --profile search up -d

# Local LLM inference via Ollama
docker compose --profile ollama up -d

# Full containerized stack (Elixir app in Docker too)
docker compose --profile full up -d
```

### Dashboards

| URL | What |
|-----|------|
| `localhost:4000/substrate` | Live cognitive state |
| `localhost:4000/substrate/thoughts` | Live thought tree |
| `localhost:4000/substrate/compare` | Two-agent divergence observatory |
| `localhost:4000/goals` | Goal management (CRUD, approve/reject) |
| `localhost:4000/narrative` | Autobiographical reflections |
| `localhost:4000/chat` | Conversation interface |

### MCP Server

Lincoln exposes an MCP (Model Context Protocol) server at `http://localhost:4000/mcp` with tools for external integration:

- `observe(content)` — inject an observation into the substrate
- `get_state()` — read current cognitive state
- `list_agents()` — enumerate agents
- `start_substrate()` / `stop_substrate()` — control the cognitive loop

### Useful Make Targets

```bash
make dev          # Start dev (Docker services + local Elixir)
make test         # Run test suite
make lint         # Format check + Credo strict
make precommit    # All checks before committing
make iex          # IEx with Lincoln loaded
make db-console   # PostgreSQL shell
make status       # System health check
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | Yes (prod) | — | Claude API key for frontier inference |
| `ML_SERVICE_URL` | Yes (prod) | `http://localhost:8000` | Python embedding service URL |
| `DATABASE_URL` | Yes (prod) | `postgres://postgres:postgres@localhost:5432/lincoln_dev` | PostgreSQL connection |
| `SEARXNG_URL` | No | — | SearXNG base URL for self-hosted search |
| `TAVILY_API_KEY` | No | — | Tavily API key (1000 free queries/month) |
| `FIRECRAWL_API_KEY` | No | — | Firecrawl API key for search + scrape |
| `CONTEXT7_API_KEY` | No | — | Context7 API key for library documentation |
| `LINCOLN_FETCH_ENABLED` | No | `false` | Enable Fetch MCP server for page reading |
| `LLM_PROVIDER` | No | `anthropic` | LLM provider (`anthropic` or `openai`) |
| `OPENAI_API_KEY` | No | — | OpenAI API key (if using `openai` provider) |

### Search Provider Precedence

The search adapter is auto-configured at startup based on which env vars are set:

1. If `SEARXNG_URL` is set → SearXNG is first in cascade (free, unlimited)
2. If `TAVILY_API_KEY` is set → Tavily is added to cascade (1000 free/month)
3. If `FIRECRAWL_API_KEY` is set → Firecrawl is added to cascade (search + scrape)

When multiple providers are configured, they form a cascade: first provider that returns non-empty results wins. All results are cached in ETS for 1 hour.

If no search providers are configured, investigation still works — it just uses LLM reasoning over existing beliefs and memories without web grounding.

## Project Structure

```
lincoln-project/
├── apps/
│   ├── lincoln/                    # Main Elixir application
│   │   ├── lib/lincoln/
│   │   │   ├── substrate/          # Core cognitive processes
│   │   │   │   ├── substrate.ex    #   Tick loop orchestrator
│   │   │   │   ├── attention.ex    #   Parameterized belief scoring
│   │   │   │   ├── thought.ex      #   OTP thought processes
│   │   │   │   ├── skeptic.ex      #   Contradiction detection
│   │   │   │   ├── resonator.ex    #   Coherence/cascade detection
│   │   │   │   ├── cognitive_impulse.ex  # Impulse types + scoring
│   │   │   │   ├── goal_thought.ex       # Goal pursuit reasoning
│   │   │   │   ├── goal_review_thought.ex # Goal relevance review
│   │   │   │   ├── investigation_thought.ex # Question → search → belief
│   │   │   │   └── conversation_bridge.ex   # Chat ↔ substrate bridge
│   │   │   ├── goals/              # Goal system
│   │   │   │   ├── goal.ex         #   Ecto schema
│   │   │   │   ├── decomposer.ex   #   HTN-style goal decomposition
│   │   │   │   ├── method_library.ex #  Cached decomposition methods
│   │   │   │   └── self_proposer.ex  #  Lincoln proposes its own goals
│   │   │   ├── mcp/                # MCP + search infrastructure
│   │   │   │   ├── search_client.ex         # SearchClient behaviour
│   │   │   │   ├── search_client_searxng.ex # SearXNG adapter
│   │   │   │   ├── search_client_tavily.ex  # Tavily adapter
│   │   │   │   ├── search_client_firecrawl.ex # Firecrawl adapter
│   │   │   │   ├── search_client_cascade.ex # Cascading fallback
│   │   │   │   ├── search_client_cached.ex  # ETS cache wrapper
│   │   │   │   ├── search_cache.ex          # ETS cache + rate limiter
│   │   │   │   └── client.ex               # Unified MCP tool calling
│   │   │   ├── beliefs.ex          # Belief CRUD + AGM revision
│   │   │   ├── memory.ex           # Memory recording + retrieval
│   │   │   ├── goals.ex            # Goal context module
│   │   │   ├── questions.ex        # Investigation question pipeline
│   │   │   ├── cognition/          # Conversation processing
│   │   │   │   └── conversation_handler.ex  # Full cognitive pipeline
│   │   │   └── autonomy/           # Self-modification + learning
│   │   ├── lib/lincoln_web/        # Phoenix + LiveView UI
│   │   ├── config/                 # App configuration
│   │   └── test/                   # Test suite (290 tests)
│   └── ml_service/                 # Python embedding service
│       ├── main.py                 #   FastAPI + sentence-transformers
│       └── Dockerfile
├── config/
│   └── searxng/settings.yml        # SearXNG engine configuration
├── docker-compose.yml              # Service orchestration
├── Makefile                        # Development tasks
├── .env.example                    # Environment template
└── writeup.md                      # Full research narrative
```

## Status

Research-grade exploration in active development. Not production software. The substrate runs, beliefs revise, goals pursue, investigation searches the web, and the self-modification pipeline has produced real commits. The system maintains ~97% local computation (Level 0) with expensive LLM calls reserved for high-attention moments.

Current capabilities:
- Continuous cognitive loop with parameterized attention
- AGM belief revision with confidence, entrenchment, and source credibility
- Goal creation, pursuit, decomposition, and periodic relevance review
- Web search grounded in Lincoln's own questions (SearXNG/Tavily/Firecrawl cascade)
- Conversation with goal detection, web search, and full belief/memory context
- Self-modification pipeline with safety guardrails
- Two-agent divergence observatory

Known limitations are documented in `LEARNINGS.md` and are the next work.

## Stack

- **Runtime:** Elixir 1.17+ / OTP 27+
- **Process management:** DynamicSupervisor, Registry, GenServer
- **Web:** Phoenix 1.8 + LiveView 1.1
- **Database:** PostgreSQL 16 + pgvector
- **Background jobs:** Oban (legacy workers, migrating to substrate)
- **Frontier LLM:** Anthropic Claude API
- **Local LLM:** Ollama (Qwen 2.5, Gemma 3, Phi-4, Llama 3.3)
- **Embeddings:** Python sentence-transformers (384-dim, all-MiniLM-L6-v2)
- **Search:** SearXNG (self-hosted) + Tavily + Firecrawl (cascading)
- **UI:** Tailwind CSS v4 + DaisyUI
- **Code quality:** Credo (strict mode)

## License

MIT

---

*"You want to go to the island? I am the island."*
