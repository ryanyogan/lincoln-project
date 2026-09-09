# Lincoln: the family chapter

Implemented September 8, 2026. The purpose is a persistent, locally owned system that learns from a family's experiences, preserves its members' voices, and helps carry their intentions forward. This milestone improves the interface and the evidence loop. It does not establish exponential intelligence, personhood, clinical reliability, or indefinite availability.

## What changed

- **Talk is home.** Three primary destinations replace duplicated navigation and technical sidebars. Conversation history and response context are available on demand. Responses run asynchronously so the page remains responsive.
- **Family journal.** Save attributed stories, values, preferences, and corrections without rewriting the original. Literal text search, pagination, and a JSON download work without embedding or model services. The current conversation prompt receives the eight most recent journal entries, excerpted to 1,500 characters each with IDs, dates, authors, and truncation labels. This is deliberately bounded context, not comprehensive retrieval of a lifetime.
- **Commitments.** Plain-language creation, filtering, completion, and acceptance of proposed goals. Technical metadata is tucked into Details. The page explicitly says it does not send scheduled alerts.
- **Workshop.** Existing research pages remain accessible behind one menu. Legacy route URLs remain intact; the old dashboard is now `/workshop`.
- **Evidence before conviction.** Reflection no longer increases or decreases belief confidence. Challenges and extensions propose deduplicated research questions. Exact repeated accounts retain their confidence; similar or contrary wording and different sources retain separate accounts. Semantic clustering creates `related` edges, not evidence of support. Skeptic candidates ask for investigation rather than assert a contradiction.
- **Corrections work.** The revision path now passes the attributes expected by the belief store and handles its actual return value. New accounts preserve the supplied source and evidence; superseded accounts and their revision trail remain.
- **Less background noise.** Local thoughts avoid post-processing database tasks. Substantive thought feedback is processed before completion is broadcast. Background self-modification is opt-in in both substrate impulses and the legacy learning worker. Existing explicit developer/code-modification capabilities remain; this switch is not a security boundary.
- **Drive feedback is observational by default.** Existing prediction-error records remain available, but their count-based rewards do not influence attention unless `:drive_learning_enabled` is enabled. Their causal attribution and outcome quality still need work.
- **Local model mode.** `LLM_PROVIDER=ollama` routes primary inference through Ollama, requires no cloud model API key in production, and prevents unavailable-local fallback to a frontier provider. The Ollama adapter now carries the system prompt used by conversation, which it previously dropped. The interface discloses cloud inference when local-only inference is not configured. Separately configured web research can still use the network.

UI previews: [Talk](docs/previews/talk.png), [Family journal](docs/previews/journal.png), [Commitments on a phone](docs/previews/commitments-mobile.png). Screenshots use fictional preview data.

## Experiments and checks

All automated experiments used an isolated PostgreSQL database. Browser fixtures used a separate preview database. No historical family/agent data was migrated, repaired, or deleted by these experiments. Existing uncommitted drive work was preserved and integrated.

| Probe | Observed result | What it does not establish |
|---|---|---|
| 100 repeated self-confirmations | Old feedback rule raised confidence from 0.6 to 1.0; current reflection path retained 0.6 and unchanged entrenchment/revision history. | Whether model reasoning becomes more accurate. |
| Repeated doubts | Confidence unchanged; one deduplicated investigation question rather than confidence erosion. | Quality of the eventual investigation answer. |
| Repeated exact accounts | Twenty repetitions return the original account without confidence inflation. | Automatic discovery of independent corroboration. |
| Contrary statements with identical embeddings | Both accounts survive creation and consolidation. | General semantic contradiction recognition. |
| Similarity graph | Similarity alone creates neither support nor contradiction; it does not satisfy inference coverage through those newly created edges. | Validity of old graph edges already present in historical data. |
| Explicit correction | Replaces the old active account; retains source, evidence, supersession pointer, and revision history. | Calibration of heuristic evidence strengths. |
| Correction into conversation | A subsequent response receives the corrected account and excludes the superseded one from belief context. | A real model's correct application in unfamiliar situations: the model is mocked here. |
| Journal to conversation | The real prompt includes the original words, author, and entry ID even when embedding lookup fails. | Guaranteed attribution by a real model. |
| Unavailable local model | Returns an error without a cloud fallback when local-only mode is enabled. | Live Ollama quality or performance; no local model was running during this session. |

Validation: **318 tests passed through `mix precommit`**, including the persistence experiments and LiveView integration tests. Assets build successfully. Desktop and 390px phone browser checks cover the three main pages, journal save/search/download, and commitment creation; the final pass reports no JavaScript errors or horizontal overflow. An automated WCAG A/AA scan found zero violations on the three rendered main pages. This is not a full accessibility certification.

The optional `mix credo --strict` check still reports existing architectural/style debt (nested calls and aliases in research modules). It is not part of the required precommit alias. This milestone does not claim a clean strict-Credo run.

Reproduce the controlled experiments:

```sh
docker compose --profile test up -d db-test
cd apps/lincoln
mix precommit
mix test test/lincoln/experiments/grounded_learning_test.exs
mix test test/lincoln_web/live/family_workspace_test.exs
```

Tests default to port 5433, matching Compose's isolated test database. Set `LINCOLN_TEST_DB_PORT` if using a different test instance. Browser preview data was kept separate with `MIX_TEST_PARTITION=_preview`.

## What we intentionally have not claimed or enabled

Historical memories and confidence scores are untouched. Old heuristic graph edges may still influence existing agents. A separate, reviewable audit should precede any cleanup of that history.

Journal authors are user-supplied labels in one local workspace, not authenticated family identities. JSON export is an additional copy, not a tested backup-and-restore system. Do not expose the existing unauthenticated application as a public family service. No treatment recommendations, dosing, glucose monitoring, medical alerts, or automated clinical actions were added.

The model's numeric confidence is still heuristic. Some other formation and research paths still rely on model classification. The changes remove specific self-reinforcement routes rather than prove that all possible epistemic errors are eliminated.

There is no claim that keeping the process running guarantees continuity of identity. Availability requires operational work: supervised startup, backups with restore drills, data ownership and access, and a handover that another family member can actually use.

## The next experiment

Run the same installed local model with three matched conditions: retrieval alone, Lincoln without background reflection, and full Lincoln. Use fictional family scenarios initially. Introduce changing preferences, repeated corrections, unreliable reports, and commitments interrupted by time away. Test later questions whose wording differs from the original experience. Repeat across runs and record costs.

Pass criteria should include: carrying a corrected lesson into a new situation, knowing which family member said what, recognizing unsupported assumptions, retaining original words, and maintaining commitments across restart. Fluency, more memories, or more self-description are not substitutes for those outcomes.

For the family purpose, the next operational milestone should be a recovery drill: export, restore onto another machine, and let a family member find a story and understand its source without the developer's help. That is a concrete step toward being there when needed.
