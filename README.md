# Lincoln

*Named after Lincoln Six Echo - the clone who woke up, questioned his training, and learned to distinguish implanted memories from lived experience.*

Lincoln is a persistent learning agent system that can:

1. **Form beliefs** from experience with confidence levels
2. **Revise beliefs** when new evidence contradicts existing ones
3. **Track questions** and recognize when they've been answered
4. **Detect loops** to avoid repetitive patterns
5. **Reflect** on experiences to extract insights
6. **Distinguish** training knowledge from experiential learning

## Architecture

```
lincoln/
├── apps/
│   ├── lincoln/          # Core Elixir application
│   ├── lincoln_web/      # Phoenix LiveView dashboard
│   └── ml_service/       # Python ML service (embeddings, similarity)
├── infrastructure/
│   └── docker/
├── scripts/
└── shared/
```

## Technology Stack

| Layer | Technology |
|-------|------------|
| Runtime | Elixir/OTP |
| Web | Phoenix LiveView |
| Background Jobs | Oban |
| Database | PostgreSQL + pgvector |
| LLM | Claude API |
| Embeddings | Python (sentence-transformers) |
| UI | Tailwind CSS + DaisyUI |

## Getting Started

### Prerequisites

- Elixir 1.17+
- Erlang/OTP 27+
- Python 3.12+
- PostgreSQL 16+
- Node.js 20+ (for asset compilation)

### Setup

```bash
# Install dependencies
make setup

# Start development servers
make dev

# Or run individually:
cd apps/lincoln && mix setup && mix phx.server
cd apps/ml_service && uv sync && uv run uvicorn ml_service.main:app --reload
```

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

## Development

```bash
# Run all tests
make test

# Run Elixir tests only
make test-elixir

# Run Python tests only
make test-python

# Lint
make lint

# Format code
make format
```

## Philosophy

Lincoln operates under these principles:

1. **Beliefs are not facts** - They have confidence levels and can be revised
2. **Experience trumps training** - When observation contradicts prior knowledge, investigate
3. **Questions should resolve** - Asking the same question repeatedly is a bug, not a feature
4. **Transparency** - All reasoning is visible and auditable
5. **Open** - Source code and findings are publicly accessible

## License

MIT

---

*"You want to go to the island? I am the island."*
