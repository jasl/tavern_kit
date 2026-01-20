# ConversationRun (Run-driven scheduler)

This doc describes how **ConversationRun** provides a single, explicit runtime unit for AI generation.

For the overall architecture, see `PLAYGROUND_ARCHITECTURE.md`.

For TurnScheduler performance work, see `TURN_SCHEDULER_PROFILING.md`.

## Why runs exist

- Keep runtime state out of `Space`, `Conversation`, and `Message`.
- Provide safe concurrency constraints (at most one running run per conversation).
- Support debounce, cancel/restart policies, regenerate swipes, and auto-without-human followups.

## Data model

`conversation_runs` is a state machine table keyed by UUID.

Key columns:

- `conversation_id` (owner conversation)
- `conversation_round_id` (nullable; links TurnScheduler-managed runs to an active round)
- `kind`: `auto_response | auto_user_response | regenerate | force_talk`
- `status`: `queued | running | succeeded | failed | canceled | skipped`
- `reason` (human-readable reason, e.g., `user_message`, `force_talk`, `auto_user_response`)
- `speaker_space_membership_id` (who is speaking for this run)
- `run_after` (debounce / delayed scheduling)
- `cancel_requested_at` (soft-cancel signal for user interruption policies)
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

### Expected tail guard (TurnScheduler queued runs)

TurnScheduler-created runs include a lightweight guard to prevent stale queued work:

- `TurnScheduler::Commands::ScheduleSpeaker` sets `run.debug["expected_last_message_id"]` to the
  **scheduler-visible tail** message id at schedule time.
- `Conversations::RunExecutor::RunClaimer` compares it to the **current scheduler-visible tail**
  (ignoring `visibility="hidden"` messages).
- If the tail changed (new message, or soft delete/hide), the run is marked `skipped`
  (`error.code = "expected_last_message_mismatch"`), and TurnScheduler can advance safely.

See `MESSAGE_VISIBILITY_AND_SOFT_DELETE.md` for how soft delete interacts with this guard.

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

The activated speaker queue for a round is persisted in:

- `conversation_round_participants` (ordered by `position`)
- `conversation_rounds.current_position` (0-based index into the queue)

This queue is computed once when a round starts and **never recalculated mid-round**. This ensures:

- Deterministic turn order regardless of membership changes
- No race conditions from concurrent queue recalculations
- Consistent behavior across multi-process deployments

Note:

- A speaker may appear **multiple times** in a queue (manual insertion). Treat `conversation_round_participants` as queue *slots* (position-based), not a unique set.

## Performance profiling (dev)

Set `TURN_SCHEDULER_PROFILE=1` to log SQL query counts and timings for TurnScheduler hot paths
(`ActivatedQueue`, `QueuePreview`, `Broadcasts.queue_updated`).

## Common flows

### User turn (normal chat)

1. User creates a `Message(role: "user")`.
2. `Message.after_create_commit` calls `TurnScheduler.advance_turn!`.
3. `AdvanceTurn` command:
   - If idle, starts a new round via `StartRound`
   - `StartRound` computes the activated speaker queue using `Queries::ActivatedQueue` (aligned with SillyTavern/RisuAI semantics by `Space.reply_order`)
   - Persists queue on the round (`conversation_round_participants`, `current_position`)
   - `ScheduleSpeaker` creates a `ConversationRun(status: "queued")` and kicks `ConversationRunJob`
4. Executor claims run → `running`, builds prompt, calls LLM, then creates the final message and marks run `succeeded`.
5. The newly created message again triggers `TurnScheduler.advance_turn!`, which:
   - Uses persisted `conversation_round_participants` to determine next speaker (no recalculation)
   - Advances `current_position` and schedules next speaker
   - When queue exhausted: resets to `idle` or starts new round if auto scheduling enabled

**Note**: The assistant message is created with its final `generation_status` directly (no intermediate "generating" state for new messages). This eliminates race conditions between `broadcast_create` and subsequent status updates.

### Regenerate (swipe)

1. Planner stops any active scheduling round (strong isolation), then creates/upserts a `queued` run of kind `regenerate` with a target message id in `debug`.
2. Executor generates a new assistant version and **adds a `MessageSwipe`** on the target message (Turbo Streams replace).
3. Target message's `generation_status` is updated to `"succeeded"` after regeneration completes.

### During AI Generation: user input policy (`Space.during_generation_user_input_policy`)

This setting controls what happens when a **human** sends a new message while an AI run is `queued`/`running`.

Policies:

- `reject` (ST/Risu-like): lock input; user must wait or Stop first.
- `restart` (ChatGPT-like): interrupt in-flight generation; respond from latest user input.
- `queue` (merge-friendly): allow input anytime; each new user message results in a new AI response (single-slot queue overwrites allow “merge”).

#### `reject` (lock input)

- UI: input is disabled while scheduler state is `ai_generating`.
- Server: message creation returns `423 Locked` (generation_locked) when any active run exists (`queued` or `running`).

#### `restart` (interrupt AI)

If a user message arrives while a run is `running`:

- mark the running run with `cancel_requested_at` (Stop generate semantics: cancel + discard output)
- cancel any queued run (user message takes priority)
- stop the current round (strong isolation), then the new user message starts a fresh round via `after_create_commit`

Effect:

- the in-flight reply is discarded
- the next reply is generated from the newest context (latest user message)

#### `queue` (allow input; single-slot queue overwrites)

- user messages are always allowed (even if a run is `queued`/`running`)
- any existing queued run is canceled (user input takes priority)
- the current running run is NOT canceled
- the user message starts a new round after commit; if a run is already running, the new queued run is created but not kicked until the running run finishes

Key safety property:

- a late assistant message from the previous run is treated as **stale** and must not cancel the queued reply for the newest user message.

#### Debounce / merge (`Space.user_turn_debounce_ms`)

Debounce delays scheduling the first speaker when a round is started from **human** input. With single-slot queue overwrite semantics, rapid user messages naturally coalesce:

- first user message starts a round and creates a queued run with `run_after` in the future
- second user message before `run_after` cancels the queued run and starts a fresh round (new queued run)
- result: only one AI response is generated, and it sees the latest combined context

### User stop (Stop generating) → decision point (Retry / Skip)

User-initiated Stop is treated as a “decision point” instead of “conversation stuck”:

- Stop requests cancel on the running run (`cancel_requested_at`).
- The current round transitions to `paused` to prevent auto-advancement.
- UI presents recovery actions:
  - Retry current speaker (same round)
  - Skip current speaker (advance immediately)

This differs from `StopRound` which is a stronger recovery boundary (explicitly ending the round).

## Stale recovery

Runs emit `heartbeat_at` while running. A reaper job (`ConversationRunReaperJob`) detects staleness and fails the run as a last-resort safety net.

When a stale run is recovered:
- The run is marked as `failed`
- Any messages with `generation_status: "generating"` are updated to `generation_status: "failed"` with an error message
- UI receives `stream_complete` event to clear typing indicators

### Scheduler failed-state (TurnScheduler-managed runs)

For runs created by TurnScheduler (`run.debug["scheduled_by"] == "turn_scheduler"`), failures are treated as **unexpected** and should block progress until a human decides how to recover:

- The active `ConversationRound` is set to `scheduling_state="failed"` **without clearing the current round state**
  - Keeps: current round id, current speaker position, and participants queue
- Any queued runs are canceled to avoid automatic progression after a failure
- Auto without human and Auto are disabled immediately to make the recovery boundary explicit
- UI shows a blocking error alert and the user can Retry
- If the user sends a new **human** message, the backend treats it as an implicit `StopRound`:
  - cancels the failed round and starts a fresh round from the new input (when `reply_order != manual`)
- Retry semantics: **retry the same speaker in the same round** (resume from where it failed)

This makes failure recovery explicit and prevents cascading errors from silently advancing the schedule.

## Round association (TurnScheduler)

`conversation_runs.conversation_round_id` is the single structured link between a run and a persisted round:

- TurnScheduler-managed runs always set `conversation_round_id` to the active `ConversationRound.id`.
- Independent runs (`force_talk`, `regenerate`) intentionally keep it `NULL`.
- Round records are periodically cleaned up, so this FK is `on_delete: :nullify` and must be treated as optional.

This relationship is used for:
- stale/late message protection (ignore messages from runs belonging to a different round)
- strict recovery guards (Skip/Retry/HandleFailure use expected round equality)

## Strong isolation for independent runs

`force_talk` / `regenerate` are treated as timeline operations that must not mutate an active round:

- Planning `force_talk` / `regenerate` first executes `StopRound` to cancel any active round + queued scheduler run.
- `AdvanceTurn` ignores messages from runs with `conversation_round_id = NULL` when an active round exists.

This prevents "independent run overwrote the queue / polluted the round" surprises.

## Pause / Resume (group chats)

TurnScheduler supports an explicit `paused` scheduling state on the active round:

- `PauseRound`: sets `scheduling_state="paused"` and cancels the queued scheduler run for the round.
- While paused, `AdvanceTurn` records progress (spoken + cursor) but never schedules the next speaker.
- `ResumeRound`: resumes only if there are no active runs (queued/running), and schedules immediately (no `auto_without_human_delay_ms`).

## Manage round queue (group chats)

For group chats, the UI provides a “Manage round” modal that edits the persisted participant queue for the active round (`conversation_round_participants`).

Capabilities:

- **Add speaker**: appends a new `pending` slot to the **end** of the current round queue (duplicates allowed).
- **Reorder**: drag-and-drop reorders only the **editable** portion of the queue:
  - while `ai_generating`: editable starts at `current_position + 1` (current slot is read-only)
  - while `paused`: editable starts at `current_position` (current slot is editable)
- **Remove speaker**: removes a `pending` slot only within the editable portion (cannot remove already-spoken/skipped slots).

All operations are applied under `conversation.with_lock` and broadcast via `TurnScheduler::Broadcasts.queue_updated` so other open tabs can stay in sync.
