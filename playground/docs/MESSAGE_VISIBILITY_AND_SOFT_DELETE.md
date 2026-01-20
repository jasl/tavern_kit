# Message visibility + soft delete (Playground)

This doc specifies how message **visibility** (`normal` / `excluded` / `hidden`) works in the Playground Rails app, and how **soft delete** ("delete message") interacts with **TurnScheduler** and **ConversationRun**.

本文档也作为审查用的“行为规格”，重点说明：

- 软删除（`visibility="hidden"`）在不同运行状态下的处理策略（idle / queued / running / active round）。
- 对调度的影响：TurnScheduler 的 epoch / last-speaker / active round / queued run 如何被保护，避免 orphan reply 或卡死在 `ai_generating`。

Related docs:

- `CONVERSATION_RUN.md` — Run state machine and TurnScheduler fundamentals
- `BRANCHING_AND_THREADS.md` — Fork points and branching invariants
- `SPACE_CONVERSATION_ARCHITECTURE.md` — Model overview and key invariants

---

## 1) Visibility model

Playground uses a single canonical column: `messages.visibility`.

| `visibility` | UI timeline | Prompt building | Scheduling (TurnScheduler epoch / last-speaker) |
|-------------|-------------|----------------|-------------------------------------------------|
| `normal`    | visible     | included       | participates |
| `excluded`  | visible     | excluded       | participates |
| `hidden`    | hidden      | excluded       | **does not participate** |

### Canonical scopes (single source of truth)

Do **not** hand-roll `where(visibility: ...)` in callers; use these scopes:

- `Message.ui_visible` → `visibility IN (normal, excluded)`
- `Message.included_in_prompt` → `visibility = normal`
- `Message.scheduler_visible` → `visibility IN (normal, excluded)`

Implications:

- **UI** renders only `ui_visible` messages (hidden messages do not exist in the UI).
- **PromptBuilder** includes only `included_in_prompt` messages.
- **TurnScheduler** treats `scheduler_visible` as the authoritative message view:
  hidden messages behave as if they were deleted for epoch/activation logic.

---

## 2) Soft delete ("hide") semantics

User-visible "delete message" is implemented as **soft delete**:

- Endpoint: `DELETE /conversations/:conversation_id/messages/:id`
- Implementation: `MessagesController#destroy` → `Messages::Hider`
- Data change: `message.update!(visibility: "hidden")` (**no hard delete**)

Important invariants:

- **Tail-only mutation**: rewriting timeline content is still tail-only (`edit`, `regenerate`, `switch swipes`).
- **Soft delete is allowed on any message** (except fork points) and is intentionally **NOT** guarded by `TailMutationGuard`.
  - See `app/services/tail_mutation_guard.rb`.

### Authorization & constraints

- **Allowed**: any message the current user can administer.
  - Message owner, space owner, or admin (see `Authorization#can_administer?`).
- **Forbidden**: **fork point** messages (messages referenced by a child conversation via `forked_from_message_id`).
  - See `BRANCHING_AND_THREADS.md` for fork point definition.

### Broadcast / UI behavior

When a message is hidden successfully:

- `message.broadcast_remove` removes the message DOM element for all subscribers.
- `Messages::Broadcasts.broadcast_group_queue_update(conversation)` refreshes scheduling UI state.

On reload / pagination, hidden messages stay hidden because controllers query `Message.ui_visible`.

Idempotency:

- `Messages::Hider` treats hiding an already-hidden message as a no-op success.
- In normal UI flows, `MessagesController#set_message` uses `ui_visible`, so hidden messages are not addressable via the standard delete endpoint.

---

## 3) Scheduler safety: rollback vs non-rollback

Hiding messages is a timeline mutation that can invalidate queued/running AI work. Playground uses a conservative safety rule to avoid orphaned replies or stuck scheduling state.

Terminology:

- **Active run**: `ConversationRun.status IN (queued, running)` (see `ConversationRun.active`)
- **Active round**: `ConversationRound.status = active`
- **Scheduler-visible tail**: the last message in `conversation.messages.scheduler_visible.order(seq: :desc, id: :desc)`

### Non-rollback path (safe history cleanup)

If the conversation has:

- no active run, **and**
- no active round

Then hiding a message is treated as **non-rollback**:

- Only action: set `visibility="hidden"`
- Scheduling state is unchanged (no cancel / no round mutation)

This is the default for “delete old history messages” in an idle conversation.

### Rollback path (scheduler reliability)

Otherwise, hiding is treated as a rollback boundary:

1. **If there is a running run**:
   - Call `request_cancel!` (Stop generate semantics: cancel + discard output).
   - This is equivalent to “Stop generate”: it prevents the executor from committing final output.

2. **If the message is scheduler-sensitive**:
   - If the message is the **scheduler-visible tail**, OR
   - it is `active_round.trigger_message_id`

   Then:

   - Cancel any *downstream* queued run (single-slot queue; we cancel at most one queued run):
     - TurnScheduler-managed run: `run.debug["scheduled_by"] == "turn_scheduler"`
     - Legacy user-message run: `run.debug["trigger"] == "user_message"` and `run.debug["user_message_id"] == message.id`
     - Other queued runs (e.g. `force_talk`) are intentionally **not** canceled by soft delete.
   - Cancel the active round (`ConversationRound.status="canceled"`, `ended_reason="message_hidden"`).

3. Finally, hide the message (`visibility="hidden"`).

All mutations are done inside `conversation.with_lock` to prevent races with scheduler commands.

Why cancel the active round on tail/trigger hide?

- TurnScheduler round state is explicitly persisted in `conversation_rounds` and is driven by message creation.
- Hiding the **trigger** or **tail** can invalidate the round’s “current epoch” boundary.
- Canceling the active round ensures the UI/scheduler does not remain stuck in `ai_generating` without a valid run to finish it.

---

## 4) Extra reliability: queued runs self-invalidate on tail change

Even with rollback logic, a queued TurnScheduler run might become stale if the conversation advances before execution.

Playground adds a guard on TurnScheduler-created runs:

- `TurnScheduler::Commands::ScheduleSpeaker` sets:
  - `run.debug["expected_last_message_id"] = <scheduler-visible tail message id at schedule time>`
- `Conversations::RunExecutor::RunClaimer` checks:
  - the **current scheduler-visible tail** (ignoring hidden messages)
  - mismatch ⇒ mark run `skipped` with error code `expected_last_message_mismatch`

Effect:

- Hiding the tail (or sending a new message) before a queued TurnScheduler run executes causes that run to **skip**.
- TurnScheduler can then **advance** and schedule the next speaker instead of getting stuck in `ai_generating`.

Note:

- `Messages::Hider` proactively cancels certain queued runs when hiding a scheduler-sensitive message (tail/trigger).
- The `expected_last_message_id` guard is still valuable as a second line of defense against races
  (e.g., tail changes between scheduling and execution without an explicit cancel).

---

## 5) Common scenarios (behavior matrix)

| Scenario | Expected behavior when hiding a message |
|----------|-----------------------------------------|
| **Idle** (no active run, no active round) | Just hide; no scheduler changes |
| **Queued run exists** + hide **non-tail** message | Just hide; queued run remains |
| **Queued run exists** + hide **scheduler-visible tail** | Cancel TurnScheduler queued run (or legacy user_message run if tied to this message); cancel active round if present; hide |
| **Running run exists** + hide any message | Request cancel (Stop generate) |
| **Running run exists** + hide **tail/trigger** | Request cancel + cancel active round + cancel downstream queued run + hide |
| **Active round exists** (no run) + hide **non-tail/non-trigger** | Just hide; active round remains |
| **Active round exists** (no run) + hide **tail/trigger** | Cancel active round; hide |
| Hide a **fork point** | Forbidden (422) |

---

## 6) Forking / export: hidden must not leak

To ensure hidden messages do not re-appear indirectly:

- **Fork/branch/checkpoint cloning** uses `Message.scheduler_visible`:
  - hidden messages are omitted
  - `excluded` visibility is preserved
- **Export** (`Conversations::Exporter`) uses `Message.scheduler_visible`:
  - hidden omitted
  - excluded marked (`excluded_from_prompt: true`) and `visibility` is exported explicitly

---

## 7) Code pointers (for reviewers)

- Soft delete service: `app/services/messages/hider.rb`
- Controller endpoint: `app/controllers/messages_controller.rb#destroy`
- Tail-only guard: `app/services/tail_mutation_guard.rb` (delete is not guarded)
- Scheduler-visible reads:
  - `Message.scheduler_visible` (canonical scope)
  - `Conversation#last_user_message` / `#last_assistant_message`
  - `TurnScheduler::Queries::*` (ActivatedQueue / QueuePreview / NextSpeaker)
- Queued-run tail guard:
  - `TurnScheduler::Commands::ScheduleSpeaker` (`expected_last_message_id`)
  - `Conversations::RunExecutor::RunClaimer` (scheduler-visible tail check)
