# Lincoln: assessment before further development

Reviewed September 8, 2026. Scope: published article, repository documentation, current source including uncommitted drive changes, saved April state, and primary-source research. This is a static architectural assessment, not a fresh runtime experiment. No application code changed and no autonomous processes started. Historical snapshots are not measurements of today's implementation.

## What the project is trying to become

My reading of [the original April 6 article](https://ryanyogan.com/writing/building-agent-memory-from-research-to-reality) and the user's present framing: Lincoln is an attempt to build a local individual whose encounters change its beliefs, attention, relationships, and subsequent choices. Remembering information is necessary infrastructure; becoming a particular individual through history is the actual ambition. The naming story makes epistemic independence especially important: distinguishing inherited claims from observed events and revising a worldview when they conflict.

This is worth investigating. It does not require claiming that execution implies experience, or that autobiography proves personhood. Operationally, the question is whether a persistent history causes durable behavioral differences that cannot be explained by a persona prompt, retrieval alone, or random sampling.

## What is actually present

| Capability | Source evidence | Assessment |
|---|---|---|
| Persistent orchestration | `apps/lincoln/lib/lincoln/substrate/agent_supervisor.ex`, `substrate.ex`, `thought.ex` | Real supervised state and thought lifecycles. Current supervisor has Substrate, Attention, and ThoughtSupervisor children. Skeptic and Resonator are now functions called periodically, despite older five-process diagrams. |
| Belief history | `beliefs.ex`, `beliefs/belief_revision.ex`, `cognition/belief_revision.ex` | Explicit confidence, entrenchment, provenance labels, supersession, relationships, and revision records. A valuable inspectable foundation. |
| Selective attention | `substrate/attention.ex`, `attention_params.ex`, `diversity_monitor.ex` | Real scoring, interruption policies, and responses to repetitive focus. Differentiated attention is implemented; durable personality is still a hypothesis. |
| Experience intake | `perception/sources/file_inbox.ex`, `substrate/perception_thought.ex`, `conversation_bridge.ex`, `investigation_thought.ex` | User-curated files, conversation, and research give the system external inputs. This provides a practical starting environment without turning the project into a general automation assistant. |
| Conversation linkage | `cognition/conversation_handler.ex:1117`, `substrate/conversation_bridge.ex` | Current chat includes substrate state, beliefs, goals, and focus history. The old note that conversation entirely bypasses substrate context is stale. Response generation still has its own path. |
| Autobiography | `narratives.ex`, narrative helpers in `substrate/thought.ex` | Stored LLM-generated reflections with rotating anchors. Useful material for a self-history, not proof of experienced identity. |
| Self and other models | `self_model.ex`, `user_models.ex` | Self-model mostly counts completed/failed thoughts and execution tiers. User model is session-based topic extraction and style/question statistics. Neither yet supports the depth implied by the names. |
| Outcome-shaped attention | Uncommitted `drive.ex`, `drive/drive_scores.ex`, `drive/outcome_measurement.ex`, substrate integration | Particularly promising: experience feeds back into what receives attention. Currently rewards database activity and goal progress, with important attribution limitations. |
| Local execution | `substrate/inference_tier.ex`, `config/runtime.exs` | Hybrid: local computation and Ollama, plus frontier inference. Ollama-unavailable can fall back to frontier; production requires an API key. Not a demonstrated offline organism yet. |

## What has lost novelty, and what was overstated

See [RESEARCH-LANDSCAPE.md](RESEARCH-LANDSCAPE.md) for the literature comparison and its source dates. Persistent memory, reflection between interactions, autonomous scheduling, evolving memory graphs, and autobiographical agent designs already have substantial precedents. Several predate the article. Recent progress strengthens the need for a narrower experimental claim; it does not establish that Lincoln's particular goal has been solved.

The Python impossibility claim should be retired. Python tasks support cancellation and introspection; BEAM provides a particularly coherent runtime for supervision and lightweight processes, but this does not make the observable cognitive architecture categorically unreproducible. [Python task documentation](https://docs.python.org/3/library/asyncio-task.html).

The AGM claim should be narrowed to an inspired heuristic. The implementation scores evidence and protects entrenched beliefs. Formal AGM specifies properties of revision operators over belief sets; this code does not demonstrate compliance with those postulates. [AGM-style formal treatment](https://arxiv.org/abs/1604.07183).

Continuous scheduling is an implementation choice to test, not evidence of an inner life. A process can preserve causally relevant state while idle; a busy timer can produce no meaningful development. Likewise, using different software mechanisms for fast and deliberate work is useful architecture, but does not establish a literal implementation of human dual-process cognition.

Self-modifying code is peripheral to this project's strongest question. Keep it as an optional research instrument. Passing compilation, formatting, and tests establishes neither cognitive improvement nor development of identity.

## The most consequential gaps

### 1. Reflection can manufacture conviction

The saved `lincoln-cognitive-state.md` reports 6,339 reflection memories out of 6,411 total (98.9%), 37 observations, 35 conversations, and 123 open questions with none answered at that snapshot. It also records many beliefs at confidence 1.0. This is historical evidence of imbalance, not a claim that the current system still has those counts.

Later work adds reflection limits, attention diversity, question processing improvements, and narrative anchors. Those are substantive improvements. However, `thought.ex:943` still calls `strengthen_belief` after an LLM classifies a reflection as reinforcement; `beliefs.ex:353` increases numerical confidence. Agreement with one's own generated reflection is not independent corroboration. The architecture can still reward rehearsal.

The principle to establish is: internal elaboration may yield a hypothesis or clarify an argument, but its contribution to confidence must track its actual evidential basis and shared dependencies. Repeating an inherited assertion should not count as new evidence.

### 2. Relatedness is being promoted into logical evidence

`substrate/skeptic.ex` uses semantic similarity plus confidence/source/entrenchment heuristics and writes a `contradicts` relationship. `substrate/resonator.ex` creates `supports` relationships from similarity in active clusters. Similar statements can contradict; different-source statements can agree. These are plausible candidate-generation rules, not sufficient grounds for the resulting logical labels.

This also affects inference routing: `inference_tier.ex` considers a belief covered when it has enough support or derivation links. Heuristic edges can therefore affect whether further reasoning happens. The problem is epistemic, not merely cosmetic graph labeling.

### 3. Provenance labels do not establish source reliability

The hierarchy automatically prefers observation to inference, testimony, and training. In `perception_thought.ex`, extracted claims become observation beliefs. Reading a file is an observation that a file says something, not necessarily an observation that the claim is true. The distinction is central to Lincoln's founding question.

Likewise, a stored `training` label is Lincoln's provenance convention; it does not inspect the underlying model's actual training examples or rewrite its weights. Context-based revision can still be useful learning at the system level, but the mechanism should be described accurately.

### 4. The new drive rewards production before it measures learning

`drive/outcome_measurement.ex` scores counts of beliefs created, revised, retracted, relationships, answers, findings, and goal advances. This could encourage useful work, but could also reward churn. Before/after snapshots cover the whole agent, so overlapping activity can be credited to the wrong thought. Count deltas also cannot cleanly identify creation when creation and retraction occur together.

Preserve the feedback idea. Eventually measure attributable improvements in predictions, evidence quality, or externally verified outcomes instead of assuming more records means more understanding. The current drive is a heuristic outcome feedback mechanism, not a demonstrated model of active inference or human motivation.

### 5. Evaluation does not yet establish the central claim

`lib/mix/tasks/lincoln.benchmark.run.ex:218` sends sentence pairs directly to the frontier inference tier. Its accuracy measures that classification path, not the Skeptic, persistent revision, experiential transfer, or continuity. Some labels also omit the time and context needed to judge contradiction.

Self-model completion percentages measure whether computation finished, not whether a thought was true or useful. The divergence observatory is promising instrumentation, but parameter-driven divergence alone does not distinguish personality from configured sampling preferences.

## What is worth retaining

Retain the BEAM runtime, explicit belief history, observable thought processes, curated perception, attention policies, and outcome-feedback direction. They form an unusually inspectable personal research apparatus. Novel integration is a legitimate contribution when paired with a clear question and persuasive evidence; it need not be unprecedented theory.

The strongest conceptual asset is developmental individuality: a particular history producing a particular way of attending, anticipating, and relating. The important evidence is what changes in future decisions and why, not how convincingly Lincoln describes itself.

## Proposed next research step, before expanding scope

Test one claim: **Does lived history change later behavior in stable, useful, traceable ways beyond a strong memory-and-retrieval baseline?**

Use the same model, initial conditions, available inputs, and explicit compute accounting across a retrieval baseline, Lincoln with background reflection disabled, and full Lincoln. Add a run with drive adaptation disabled to isolate its effect. Include an event-driven or scheduled consolidation control to test whether frequent ticking itself contributes. Repeat runs to estimate sampling variance.

Use ordinary experiences: a recurring shared activity, a mistaken prediction, an ambiguous report, a correction repeated in different contexts, an unfinished commitment, and a long pause. Prefer a small rich world to more tools.

Measure:

- Whether repeated corrections generalize to an unfamiliar situation without another reminder.
- Whether beliefs change proportionately to independent evidence, resist repeated paraphrases, and retain a correct revision trail.
- Whether Lincoln distinguishes an event from a report about it, an inference, and an imagined episode.
- Whether commitments and learned preferences persist across restarts and absences without freezing all beliefs.
- Whether different experience streams create repeatable later differences with identical initial attention settings; separately test parameter changes on identical histories.
- Whether autobiographical statements can be traced to recorded episodes and whether relevant episodes actually influence later choices.
- Whether offline operation preserves the target behaviors, with frontier fallback disabled and measured resource use.

For the user's human-oriented goal, future design should give experiences significance beyond information acquisition: particular relationships, commitments, preferences, limited attention, and the consequences of past decisions. These are proposed behavioral mechanisms, not claims of sentience. A machine that repeatedly says it wants to be human has not, by that statement alone, acquired them.

My recommendation is to continue the project as an experiment in how an individual develops through experience. Narrow its claims, strengthen the evidence loop, and resist expanding the feature list until one longitudinal experiment shows that Lincoln's history matters.
