# Lincoln

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

## Status

Research-grade exploration in active development. Not production software. The substrate runs, the divergence demo works, the belief revision framework is functional, and the self-modification pipeline has produced real commits. The Resonator is crude by design (v1 heuristic). Trajectory recording needs richer data. Conversation currently bypasses the substrate for response generation. These limitations are documented in the codebase and are the next work.

## Stack

- **Runtime:** Elixir 1.17+ / OTP 27+
- **Process management:** DynamicSupervisor, Registry, GenServer
- **Web:** Phoenix 1.8 + LiveView 1.1
- **Database:** PostgreSQL 16 + pgvector
- **Background jobs:** Oban (legacy workers, migrating to substrate)
- **Frontier LLM:** Anthropic Claude API
- **Local LLM:** Ollama (Qwen 2.5, Gemma 3, Phi-4, Llama 3.3)
- **Embeddings:** Python sentence-transformers (384-dim, all-MiniLM-L6-v2)
- **UI:** Tailwind CSS v4 + DaisyUI
- **Code quality:** Credo (strict mode)

## License

MIT

---

*"You want to go to the island? I am the island."*
