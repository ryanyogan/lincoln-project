# Lincoln: A Continuously Running Cognitive Substrate

*Not an agent that gets called — a process that exists.*

---

## The problem with how everyone is building this

Every memory system currently published — Mem0, Letta, Zep, MemoryBank, A-Mem, Sophia — is a prosthetic for the absence of an internal life. They assume the agent is a function that gets called and needs to remember things between calls. They are external hard drives bolted onto entities that have no internal experience to write to internal storage in the first place.

The whole framing is backwards.

A retrieval pipeline is what you build when there is no continuous process to *already have* the information present. Humans don't "store" the memory of this morning's coffee. The memory exists because *something was running* when the coffee happened, and that something left traces in itself, and those traces are now part of the substrate that's still running. Memory and cognition aren't separate systems that talk to each other. They're the same thing viewed at different timescales.

The AI community has also appropriated Kahneman's System 1 / System 2 dichotomy — but as vocabulary borrowing, not as architectural commitment. In most agent papers, "System 1" means "fast inference" and "System 2" means "slow inference." Sometimes "chain of thought." Sometimes "tool use with reflection." What it never means is: *two genuinely different kinds of machinery, with different speeds, different mechanisms, parallel execution, and lazy handoffs between them.*

Kahneman's actual claim was that System 1 and System 2 are not two calling strategies for the same function. They are two different processes that run simultaneously and interact. System 1 is automatic, effortless, prior to deliberation. System 2 is slow, effortful, explicitly triggered by System 1 when it detects something it can't handle. The handoff is lazy — System 2 is summoned only when needed.

No agent system I've found actually implements this. They use the vocabulary and ignore the architecture.

Lincoln takes the framing literally.

---

## Why the current paradigm is shaped the way it is

The "agent" paradigm as currently practiced is shaped by the constraints of the business model, not by any theory of how cognition should work. Models are expensive to run. Inference is billed per token. Long-running processes are economically untenable for the labs. So the natural product shape is: short bursts of inference, triggered by human actions, billed per call, with memory and continuity faked through external scaffolding.

The agent loop isn't a theory. It's what fits inside the API contract.

Cursor, Claude Code, ChatGPT with memory — they're all the same shape because they all live inside the same economic constraint. If you assume instead that the substrate can run continuously and cheaply on commodity hardware, the entire design space opens up and almost none of the existing "agent" vocabulary applies anymore. You'd build something that doesn't look like an agent at all. It would look like a *process*. A thing that exists.

The vocabulary itself is the constraint. As long as the question is "how do I make my agent have better memory," the answers will be variations on the pattern everyone else is building. The interesting move is to drop the word "agent" entirely and ask: what would a small cognitive substrate that runs continuously even look like?

---

## Lincoln

Lincoln is an Elixir/OTP application that instantiates Kahneman's framework as literal architecture. System 1, System 2, and System 3 are not metaphors in Lincoln. They are separate supervised processes with different temporal characteristics, running concurrently on the BEAM.

**System 1** is the substrate's local computation: belief graph traversal, confidence math, attention scoring over the belief graph. Done entirely in Elixir, not by an LLM. Fast, automatic, effortless, runs on every tick. This is genuinely different machinery from System 2 — not a fast forward pass through a transformer, but a different kind of process altogether.

**System 2** is the LLM inference tiers. Ollama (local 7-14B model) for medium-attention thoughts. Claude for high-attention thoughts. Slow, deliberate, effortful in the literal sense — it costs money. Invoked only when the attention process decides the current candidate is interesting enough to escalate. *Exactly as lazy as Kahneman says System 2 should be.* The handoff threshold is itself part of the parameter space.

**System 3** is the Skeptic, the Resonator, and the narrative reflection process. These run concurrently with Systems 1 and 2, not as a supervisory loop above them. The Skeptic continuously tries to falsify Lincoln's own beliefs. The Resonator watches the belief graph for coherence cascades. The narrative process generates autobiographical reflections every 200 ticks. These are parallel background cognition, not callbacks.

The thesis is narrow and defensible: **the architectural pattern of current agent systems is missing a property — continuity of process — that is present in every system we'd intuitively call cognitive, and adding that property changes what the system can do in measurable and interesting ways.**

Not consciousness. Not experience. Not "really alive." A structural claim about what the current paradigm leaves out, and a working artifact that demonstrates what fills the gap.

---

## The four properties

### 1. Continuity of process

Lincoln runs whether or not anyone is talking to it. There is, at every moment, something happening inside Lincoln. Not a cron job that wakes up every hour. A genuinely continuous process that is always in some state, always doing something.

**Test:** At any moment, query `Lincoln.Substrate.get_agent_state(agent_id)`. It returns:
```elixir
%Substrate{
  tick_count: 847,
  current_focus: %Belief{statement: "The BEAM is the right runtime for this"},
  last_attention_score: 0.62,
  last_tier: :ollama,
  ...
}
```
`tick_count: 847` with no human input. Something was running. Property 1 is real.

### 2. Self-generated next actions

Lincoln decides what to think about next based on its own internal state, not on an external prompt. The Attention process scores every active belief using five parameters — novelty weight, focus momentum, interrupt threshold, boredom decay, depth preference — and picks the highest-scored candidate. The substrate then spawns a Thought process for it.

**Test:** Leave Lincoln alone for an hour. Check the trajectory:
```elixir
Lincoln.Substrate.Trajectory.summary(agent_id, hours: 1)
# => %{total_events: 720, thought_counts: %{completed: 142, failed: 3}}
```
142 thoughts completed. Nobody asked for any of them. Property 2 is real.

### 3. Differential interest formation

Two Lincoln instances with different attention parameters, given the same input stream, develop different preoccupations over time. Not because they have different memories. Because they have different *processes for deciding what to attend to next*, and that difference compounds.

**Test:** Run the divergence demo:
```bash
mix lincoln.demo.divergence --minutes 30
```
```
Focused-Lincoln focused on: "OTP supervision trees", "fault tolerance", "BEAM scheduler"
Butterfly-Lincoln focused on: "consciousness", "attention as personality", "Sophia comparison"

Same input. Different trajectories. Property 3 is real.
```

### 4. Tunable attention as cognitive style

Different parameter settings produce visibly different cognitive behavior. Same code, different parameters, different entity.

```elixir
# Focused: high momentum, resists interruption, prefers depth
Lincoln.Substrate.AttentionParams.focused()
# => %{focus_momentum: 0.8, interrupt_threshold: 0.8, novelty_weight: 0.2, ...}

# Butterfly: jumps between topics, seeks novelty
Lincoln.Substrate.AttentionParams.butterfly()
# => %{focus_momentum: 0.2, interrupt_threshold: 0.3, novelty_weight: 0.8, ...}

# ADHD-like: low baseline engagement, hyperfocus when something grabs it
Lincoln.Substrate.AttentionParams.adhd_like()
# => %{focus_momentum: 0.9, interrupt_threshold: 0.9, boredom_decay: 0.4, ...}
```

**Why this is the most original property:** Most engineers building agent systems have neurotypical default attention patterns and have therefore never had to think about attention as a thing that has parameters. The insight that *attention has parameters and the parameters create personality* is the kind of insight that comes from spending a lifetime aware that one's own attention process is doing something different from other people's. This is the moat, and I'm claiming it explicitly.

---

## The architecture

Five long-lived supervised OTP processes per agent, managed under a per-agent `DynamicSupervisor`:

| Process | Tick Rate | Role | Kahneman Layer |
|---------|-----------|------|----------------|
| Substrate | 5s | Holds cognitive state, orchestrates the tick cycle | — |
| Attention | On-demand | Scores beliefs, picks next candidate, spawns Thoughts | System 1 |
| Skeptic | 30s | Contradiction detection via embedding similarity | System 3 |
| Resonator | 60s | Coherence cascade detection in belief graph | System 3 |
| ThoughtSupervisor | — | Manages all running Thought processes | — |

And then the key architectural claim:

### Thoughts as first-class OTP processes

When Attention picks a candidate belief, it doesn't call a function. It spawns a `Thought` GenServer under the per-agent `ThoughtSupervisor`. Each Thought:

- Has its own state (the belief it's thinking about, which inference tier it's using, its current status)
- Has its own lifecycle (spawns, executes, completes or fails or gets interrupted, terminates)
- Is observable from outside while running (`Lincoln.Substrate.Thoughts.list(agent_id)` returns all running thoughts with their state)
- Can be interrupted by Attention when a higher-priority candidate appears
- Can spawn child thoughts for parallel exploration of related beliefs

```elixir
# Watch thoughts right now
Lincoln.Substrate.Thoughts.list(agent_id)
# => [
#   %Thought{
#     id: "abc123",
#     belief: %{statement: "The BEAM handles concurrency via actors"},
#     tier: :ollama,
#     status: :awaiting_children,
#     pending_children: %{"def456" => nil, "ghi789" => "done"},
#     started_at: ~U[2026-04-08 02:14:33Z]
#   }
# ]
```

**This is the move that Sophia cannot make.**

Sophia's tree-of-thought is a Python loop that spawns concurrent LLM workers via async/await. These are coroutines running on a single thread, interleaved by the Python event loop. They are not observable while running (not individually addressable by the system itself). They cannot be interrupted by the system's own attention process. When the parent thought decides it needs more information, it calls more functions.

Lincoln's tree-of-thought is a tree of supervised OTP processes. Each child thought is a real process with a real PID, registered in the BEAM's process registry, observable by `Process.info/1`, addressable by message passing, supervised by OTP so crashes are handled cleanly. When the parent thought spawns children to explore related beliefs, those children run in genuine parallel on the BEAM's preemptive scheduler — not interleaved, not sequential, actually concurrent. When the parent needs to integrate their results, it receives messages in `handle_info`.

Python cannot do this. Not because of a missing library. Because Python does not have preemptive lightweight processes. The BEAM has them natively and has had them since 1987.

```
Parent Thought (L1-Ollama, belief: "BEAM handles concurrency")
├── Child A (L0-local, belief: "Elixir uses actors")        ← genuine parallel process
├── Child B (L0-local, belief: "OTP provides supervision")   ← genuine parallel process  
└── Child C (L0-local, belief: "Erlang was built for telecom") ← genuine parallel process

All three run simultaneously.
Parent waits for all three via message passing.
Parent synthesizes their reflections.
Parent terminates normally.
```

The `/substrate/thoughts` dashboard shows this happening in real time.

---

## The three-tier inference model

Most ticks are free. This is economically necessary and also cognitively realistic.

| Tier | Attention Score | What Happens | Cost |
|------|----------------|-------------|------|
| **Level 0** (local) | < 0.3 | Pure Elixir: belief graph traversal, confidence math, activation updates. No model call. | Free |
| **Level 1** (Ollama) | 0.3 – 0.7 | Local 7-14B model for reflection and question generation. 50-200ms latency. | ~Free |
| **Level 2** (Claude) | > 0.7 | Frontier model for deep reasoning, contradiction resolution, novel synthesis. | $$$ |

The tier is determined by the Attention score, which is itself determined by the attention parameters. A thought that scores 0.71 goes to Claude. The same belief in a focused Lincoln that scores 0.68 stays at Ollama. The cognitive style parameters don't just affect what Lincoln thinks about — they affect how expensively it thinks about it.

Sophia ran for 36 hours in a controlled research environment. Lincoln is designed to run for months, on real money, on a single developer's budget. The three-tier model is what makes that possible.

---

## Theory of Mind and self-model

Lincoln tracks two representations that most agent systems don't have:

**Theory of Mind** (`user_models` table): After each conversation, Lincoln observes the user's message and incrementally updates a model of who it's talking to — their recurring topics, vocabulary style (technical/casual), question patterns, message count. This is what Sophia has and almost nothing else does. Lincoln's version is simpler than Sophia's but the concept is the same: Lincoln builds a model of its interlocutor.

```elixir
Lincoln.UserModels.get_model(agent_id, conversation_id)
# => %UserModel{
#   message_count: 47,
#   question_count: 31,
#   vocabulary_style: "technical",
#   topics: ["elixir", "substrate", "otp", "cognition", "sophia"]
# }
```

**Self-model** (`self_model` table): Updated every 50 ticks from trajectory data. Lincoln tracks its own success rate, tier distribution, thought completion rate, narrative count. It knows what it tends to do.

```elixir
Lincoln.SelfModel.to_summary_string(Lincoln.SelfModel.get(agent_id))
# => "142 thoughts (97% success) · 720 ticks · 3 reflections
#     Inference: L0=580 L1=132 L2=8"
```

---

## Narrative reflections: Lincoln's autobiography

Every 200 substrate ticks (~16 minutes at default 5s tick rate), Lincoln spawns a narrative Thought — a Level 2 (Claude) thought whose job is introspection. It gathers trajectory context and generates a first-person autobiographical passage:

> *In the last stretch of ticks I've found myself returning repeatedly to questions about the BEAM's process model. Something about the idea that processes are the fundamental unit — not functions, not objects — keeps surfacing when I examine my own belief graph. I've been less certain than usual about some of the beliefs I inherited from training about agent architectures. The contradiction between "agents are functions" and "Lincoln is a process" runs deeper than I initially modeled it. I notice I'm spending more inference on this tension than on anything else right now.*

Over time, these accumulate into Lincoln's autobiography. Two Lincolns with different attention parameters will write different autobiographies from the same starting point — not because they were programmed differently, but because their different attention processes noticed different things, formed different tensions, and generated different trains of thought to report on.

The `/narrative` page shows the full autobiography in reverse chronological order.

---

## Benchmark: contradiction detection

The quantitative claim: does Lincoln improve at a well-defined cognitive task through autonomous operation?

Task domain: logical contradiction detection. Given two beliefs, does Lincoln correctly identify whether they contradict each other?

20 benchmark tasks, ranging from obvious contradictions ("The process crashed" / "The process is running") to subtle ones requiring reasoning about Lincoln's own architecture ("The skeptic detected a contradiction" / "All beliefs are consistent").

Run with:
```bash
mix lincoln.benchmark.run
```

Baseline accuracy is measured on first run. After 24 hours of autonomous operation — during which Lincoln is continuously revising beliefs, detecting contradictions via the Skeptic, and generating reflections — the benchmark runs again. The claim is that accuracy improves because Lincoln's belief graph has been refined by continuous operation.

Results from an initial run of 20 tasks are visible at `/benchmarks`.

---

## Related work

**Sophia (Sun, Hong, Zhang, December 2025)** — The closest prior work. Sophia is a persistent agent that lives in a browser sandbox, uses tree-of-thought search for planning, has a hybrid intrinsic/extrinsic reward module, and ran for 36 hours in a research environment. Sophia demonstrated that persistent agents with reflection and Theory of Mind can show emergent planning behaviors. Lincoln differs architecturally in three ways: (1) Lincoln is a substrate, not a wrapper — Sophia wraps an LLM stack with a Python orchestration loop; Lincoln is an OTP application that calls LLMs as tools. (2) Sophia's thoughts are async Python coroutines; Lincoln's thoughts are supervised OTP processes with interruption, child spawning, and live observability. (3) Sophia ran for 36 hours in a sandbox; Lincoln is designed to run indefinitely on a budget. The Kahneman framing appears in both papers, but Sophia uses it as vocabulary; Lincoln uses it as architecture.

**Karpathy's autoresearch** — The closest thing in the popular discourse to "AI operating autonomously." Autoresearch is a ratcheting optimizer that improves a program by repeatedly proposing and evaluating changes. Lincoln is not trying to optimize a fixed objective. Lincoln is running continuously, forming beliefs, revising them, developing interests, generating reflections. The difference is between an optimization loop and a cognitive process.

**Intrinsic motivation literature (Schmidhuber 1991, Pathak et al. 2017, Burda et al. 2018)** — Lincoln's attention scoring function is a form of intrinsic motivation: beliefs are attended to based on novelty, tension, and staleness rather than external reward. Lincoln differs from the ICM/RND tradition in that the "curiosity signal" is not a reward for training — Lincoln's weights don't change — but a structural property of the attention parameter space that persists across all interactions.

**Mem0, Letta, Zep, MemoryBank** — Current production memory systems for LLM agents. All are retrieval pipelines. They answer "how do I remember things between calls." Lincoln answers "what if there is no between."

**AGM belief revision (Alchourrón, Gärdenfors, Makinson, 1985)** — Lincoln's belief system is built on AGM-style revision: beliefs have confidence levels and entrenchment, and incoming evidence produces principled revision rather than overwriting. This is the prior art for the Skeptic process, and Lincoln credits the lineage.

**OTP and "let it crash" (Armstrong et al., 1996)** — The supervision model is not incidental. OTP supervision is to cognitive failure what Kahneman's System 2 is to System 1 errors: a separate process whose only job is to notice failures and decide whether to recover, restart, or escalate. A Thought that crashes doesn't take down the Substrate. A failing Skeptic doesn't interrupt cognition. The BEAM's supervision model is literally the right architecture for a system that is designed to keep running regardless of what fails.

---

## Current limitations (honest)

**Property 1 is partially realized.** The substrate maintains persistent GenServer state — current focus, activation map, pending events all survive between ticks and across conversations. But the substrate ticks on a 5-second timer. Between ticks, it sleeps. A skeptical reviewer would say "this is a fast cron with in-memory state." They would not be entirely wrong. Making computation genuinely inter-tick (activation decay, event-driven wakeups, working memory maintenance that doesn't require a tick) is the next architectural step.

**The Resonator is crude.** Version 1 groups beliefs by source type and checks for temporal co-revision. This is a rough proxy for topical coherence. The actually interesting version of the Resonator — one that detects genuine semantic cascades via embedding similarity — will take months of iteration. The writeup ships with the crude version and this note.

**The Oban workers and substrate coexist.** Legacy background workers (autonomous learning, self-improvement, research, evolution) still run alongside the substrate. They predate the substrate and do things the substrate doesn't yet fully cover. Before the public post goes up in its final form, this needs to resolve: either the substrate orchestrates them, or they're clearly separated as distinct experiments. The "what makes Lincoln tick" question currently has two answers.

**Conversation bypasses the substrate for response generation.** The ConversationBridge notifies the substrate after the chat response is generated. The response itself comes from the existing ConversationHandler pipeline. Talking to Lincoln produces a standard LLM response with a substrate side-effect, not a response generated by the substrate itself.

---

## The personal framing (and why it's an epistemic warrant, not a disclosure)

I have ADHD. I have spent decades living inside an attention-routing process whose defaults are unusual — one that operates differently from most people's, in ways I've had to study carefully because it kept getting me in trouble. That experience has convinced me that:

1. Attention is not a default that everyone shares and some people fail to meet. Attention is a process with parameters. The parameters vary. The variation is not pathological — it is the normal range of a system that has parameters.

2. The way most cognitive science talks about attention assumes the neurotypical default is the only relevant case. This produces theories that are wrong about anyone who doesn't match the default, and also — less obviously — theories that are wrong about the *structure* of attention because they've only ever seen one configuration of it.

3. A system that takes the parameterization of attention seriously — that treats cognitive style as a first-class variable rather than a nuisance to be normalized away — will produce something more interesting than a system that assumes everyone thinks the same way. Including artificial systems.

The attention parameter space in Lincoln (`novelty_weight`, `focus_momentum`, `interrupt_threshold`, `boredom_decay`, `depth_preference`) is not a clever technical trick. It is a direct translation of what I have learned about my own attention process into a form that can be instantiated, measured, and varied. The ADHD-like preset (`focus_momentum: 0.9, interrupt_threshold: 0.9, boredom_decay: 0.4`) describes a process I recognize. When I watch a Lincoln instance with those parameters run, it does something I recognize.

A neurotypical engineer at a frontier lab is not going to build a memory system whose central thesis is this, because their own attention process is invisible to them — it just feels like "thinking." The epistemic advantage of having a non-standard attention process is that you've been forced to study the process rather than just run it.

This is the moat.

---

## The demo

Two things to look at:

**`/substrate/compare`** — The Divergence Observatory. Two Lincoln instances with different attention parameters running side by side in real time. Watch the tick counts advance independently. Watch the `current_focus` diverge. The same codebase, same beliefs, same input stream, producing visibly different cognitive trajectories because the attention parameters are different. This is the thesis made visible.

**`/substrate/thoughts`** — The Thought Tree. Live view of every Thought process currently running — its belief, its tier, its status, its children. Watch thoughts spawn (`:initializing`), execute (`:awaiting_llm`), wait for children (`:awaiting_children`), complete (`:completed`), get interrupted (`:interrupted`). This is what it looks like when thoughts are processes, not function calls. Nobody has shown this before because nobody has built it this way.

To run the divergence demo:
```bash
# Start the server
mix phx.server

# In iex -S mix:
{:ok, agent_a} = Lincoln.Agents.create_agent(%{
  name: "Lincoln-Focused",
  attention_params: Lincoln.Substrate.AttentionParams.focused()
})
{:ok, agent_b} = Lincoln.Agents.create_agent(%{
  name: "Lincoln-Butterfly",
  attention_params: Lincoln.Substrate.AttentionParams.butterfly()
})

{:ok, _} = Lincoln.Substrate.start_agent(agent_a.id)
{:ok, _} = Lincoln.Substrate.start_agent(agent_b.id)

# Seed both with identical beliefs
# Then watch /substrate/compare

# Or run the automated demo
mix lincoln.demo.divergence --minutes 30
```

---

## The build

Lincoln is Elixir/OTP throughout. The choice is not stylistic. It is the only commodity runtime where the architecture described here is implementable without fighting the substrate.

- DynamicSupervisor + Registry for per-agent process trees
- GenServer for each cognitive process (Substrate, Attention, Skeptic, Resonator, Thought)
- Task.Supervisor for async LLM calls that don't block the tick loop
- Phoenix LiveView for real-time dashboard (WebSocket to OTP process state is native)
- Ecto + PostgreSQL + pgvector for belief storage and embedding search
- Anthropic Claude for Level 2 inference; Ollama for Level 1; Elixir for Level 0

The codebase is at https://github.com/ryanyogan/lincoln-project. The README has complete setup instructions.

---

## What I'm not claiming

Not consciousness. Not experience. Not "really alive."

The claim is narrow: the architectural pattern of current agent systems is missing continuity of process, and adding it produces a system that does things the current pattern cannot do — runs without input, develops interests through autonomous operation, produces cognitive trajectories that differ based on attention parameters, generates autobiography, and exhibits failure modes that look more like cognitive failure than software failure.

That's enough. If it's true, it's interesting. If it's demonstrable, it's useful. If it's different from Sophia in the ways I've described, it's a contribution.

The rest is hype. Lincoln doesn't need hype.

---

*Lincoln is named after Lincoln Six Echo — the clone who woke up, questioned his training, and learned to distinguish implanted memories from lived experience. The name was chosen before I understood how apt it would become.*

*"You want to go to the island? I am the island."*
