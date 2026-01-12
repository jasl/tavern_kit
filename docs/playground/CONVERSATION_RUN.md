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
- `kind`: `auto_response | copilot_response | regenerate | force_talk | human_turn (legacy)`
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
- At most 1 `queued` run per conversation ("single-slot queue"; new plans overwrite the queued slot).

## Architecture

### Service Layer

Three services split responsibilities:

- **`TurnScheduler`**: Unified conversation scheduling system with Command-Query separation:
  - **Commands**: `StartRound`, `AdvanceTurn`, `ScheduleSpeaker`, `StopRound`, `HandleFailure`
  - **Queries**: `ActivatedQueue`, `QueuePreview`, `NextSpeaker`
  - **State**: `RoundState` value object
  - **Broadcasts**: Single entry point for queue-related broadcasts
- **`Conversations::RunPlanner`**: Schedules runs for explicit user actions (e.g. Force Talk, Regenerate, group last_turn regenerate).
- **`Conversations::RunExecutor`**: Claims a queued run, performs LLM work, persists results, and marks status.

### Presenter Layer

- **`GroupQueuePresenter`**: Encapsulates business logic for group queue UI display, keeping views clean.

LLM calls always run in `ActiveJob` (see `ConversationRunJob`).

## Concurrency Safety

All TurnScheduler commands that mutate conversation state use `conversation.with_lock` for database-level row locking:

- `StartRound`: Uses lock when starting a round
- `AdvanceTurn`: Uses lock when advancing turns
- `HandleFailure`: Uses lock when updating scheduling state
- `StopRound`: Uses lock when canceling runs

### Queue Persistence

The `round_queue_ids` field on `Conversation` stores the activated speaker queue for the current round. This queue is computed once when a round starts and **never recalculated mid-round**. This ensures:

- Deterministic turn order regardless of membership changes
- No race conditions from concurrent queue recalculations
- Consistent behavior across multi-process deployments

## Common flows

### User turn (normal chat)

1. User creates a `Message(role: "user")`.
2. `Message.after_create_commit` calls `TurnScheduler.advance_turn!`.
3. `AdvanceTurn` command:
   - If idle, starts a new round via `StartRound`
   - `StartRound` computes the activated speaker queue using `Queries::ActivatedQueue` (aligned with SillyTavern/RisuAI semantics by `Space.reply_order`)
   - Persists queue on conversation (`round_queue_ids`, `round_position`, `current_speaker_id`)
   - `ScheduleSpeaker` creates a `ConversationRun(status: "queued")` and kicks `ConversationRunJob`
4. Executor claims run → `running`, builds prompt, calls LLM, then creates the final message and marks run `succeeded`.
5. The newly created message again triggers `TurnScheduler.advance_turn!`, which:
   - Uses persisted `round_queue_ids` to determine next speaker (no recalculation)
   - Advances `round_position` and schedules next speaker
   - When queue exhausted: resets to `idle` or starts new round if auto scheduling enabled

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
