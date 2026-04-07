
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
