# ConversationRun (Run-driven scheduler)

This doc describes how **ConversationRun** provides a single, explicit runtime unit for AI generation.

For the overall architecture, see `PLAYGROUND_ARCHITECTURE.md`.

## Why runs exist

- Keep runtime state out of `Space`, `Conversation`, and `Message`.
- Provide safe concurrency constraints (at most one running run per conversation).
- Support debounce, cancel/restart policies, regenerate swipes, and auto-mode followups.

## Data model

`conversation_runs` is a state machine table keyed by UUID.

Key columns:

- `conversation_id` (owner conversation)
- `kind`: `user_turn | auto_mode | regenerate | force_talk`
- `status`: `queued | running | succeeded | failed | canceled | skipped`
- `reason` (human-readable reason, e.g., `user_message`, `force_talk`, `copilot_start`)
- `speaker_space_membership_id` (who is speaking for this run)
- `run_after` (debounce / delayed scheduling)
- `cancel_requested_at` (soft-cancel signal for restart policies)
- `started_at` (when run transitioned to running)
- `finished_at` (when run completed/failed/canceled/skipped)
- `heartbeat_at` (used to detect stale runs)
- `debug` / `error` (JSON blobs for diagnostics)

## State machine

```
queued → running → succeeded | failed | canceled | skipped
```

Concurrency invariants (DB-enforced):

- At most 1 `running` run per conversation.
- At most 1 `queued` run per conversation (“single-slot queue”; new plans overwrite the queued slot).

## Planner vs Executor

Two services split responsibilities:

- **`Conversations::RunPlanner`**: turns user actions into a queued run (and updates `run_after` for debounce).
- **`Conversations::RunExecutor`**: claims a queued run, performs LLM work, persists results, and marks status.

LLM calls always run in `ActiveJob` (see `ConversationRunJob`).

## Common flows

### User turn (normal chat)

1. User creates a `Message(role: "user")`.
2. Planner upserts a `queued` run (speaker selection + debounce).
3. Job kicks executor.
4. Executor claims run → `running`, builds prompt, calls LLM, then creates an assistant message with `generation_status: "succeeded"` and marks run `succeeded`.

**Note**: The assistant message is created with its final `generation_status` directly (no intermediate "generating" state for new messages). This eliminates race conditions between `broadcast_create` and subsequent status updates.

### Regenerate (swipe)

1. Planner creates/upserts a `queued` run of kind `regenerate` with a target message id in `debug`.
2. Executor generates a new assistant version and **adds a `MessageSwipe`** on the target message (Turbo Streams replace).
3. Target message's `generation_status` is updated to `"succeeded"` after regeneration completes.

### Restart policy during generation

If a user message arrives while a run is `running` and the space policy is “restart”:

- mark the running run with `cancel_requested_at`
- enqueue a new queued run for the latest user input

## Stale recovery

Runs emit `heartbeat_at` while running. A reaper job (`ConversationRunReaperJob`) detects staleness and fails the run so queued work can continue.

When a stale run is recovered:
- The run is marked as `failed`
- Any messages with `generation_status: "generating"` are updated to `generation_status: "failed"` with an error message
- UI receives `stream_complete` event to clear typing indicators
