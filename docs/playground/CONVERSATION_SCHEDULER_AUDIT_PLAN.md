# Conversation Scheduler Audit & Remediation Plan

Last updated: 2026-01-12

This document is the **source of truth** for:
- What was found in the TurnScheduler refactor audit
- What has already been fixed
- What still needs fixing (prioritized, with dependencies)
- How we will re-audit against the original acceptance criteria

Scope: **Playground conversation turn scheduling + runs + group chat UI behavior**, aligned with
`tmp/SillyTavern` and `tmp/Risuai` unless explicitly documented otherwise.

---

## 0) Evidence Pack (Authoritative References)

### Core runtime + scheduling
- Scheduler entry: `playground/app/services/turn_scheduler.rb`
- Commands:
  - `playground/app/services/turn_scheduler/commands/start_round.rb`
  - `playground/app/services/turn_scheduler/commands/advance_turn.rb`
  - `playground/app/services/turn_scheduler/commands/schedule_speaker.rb`
  - `playground/app/services/turn_scheduler/commands/stop_round.rb`
  - `playground/app/services/turn_scheduler/commands/handle_failure.rb` (currently unused)
- Queries:
  - `playground/app/services/turn_scheduler/queries/activated_queue.rb`
  - `playground/app/services/turn_scheduler/queries/queue_preview.rb`
  - `playground/app/services/turn_scheduler/queries/next_speaker.rb` (duplication risk)
- Run planner/executor:
  - `playground/app/services/conversations/run_planner.rb`
  - `playground/app/services/conversations/run_executor.rb`
  - `playground/app/services/conversations/run_executor/run_claimer.rb`
  - `playground/app/services/conversations/run_executor/run_followups.rb`
  - `playground/app/services/conversations/run_executor/run_persistence.rb`
- Turn driver:
  - `playground/app/models/message.rb` (`after_create_commit :notify_scheduler_turn_complete`)
  - `playground/app/services/messages/creator.rb` (reject/queue/restart policies + stop round)

### Frontend ordering + stuck recovery
- Queue UI:
  - `playground/app/services/turn_scheduler/broadcasts.rb`
  - `playground/app/presenters/group_queue_presenter.rb`
  - `playground/app/views/messages/_group_queue.html.erb`
  - `playground/app/javascript/controllers/group_queue_controller.js` (Turbo replace ordering guard)
- JSON channel + typing/streaming:
  - `playground/app/channels/conversation_channel.rb`
  - `playground/app/javascript/controllers/conversation_channel_controller.js`
  - `playground/app/javascript/controllers/message_form_controller.js` (reject policy lock)
- Stuck recovery:
  - `playground/app/services/conversations/health_checker.rb`
  - `playground/app/jobs/conversation_run_reaper_job.rb`
  - `playground/app/controllers/conversations_controller.rb` (`cancel_stuck_run`, `retry_stuck_run`, `health`)

### ST/Risu reference points used in audit
- ST group activation + pooled/natural/list/manual:
  - `tmp/SillyTavern/public/scripts/group-chats.js` (`activateNaturalOrder`, `activateListOrder`, `activatePooledOrder`)
- Risu group order (natural-ish):
  - `tmp/Risuai/src/ts/process/group.ts` (`groupOrder`)

---

## 1) Fixed in Code (Completed)

### TS-001 (P0) Queue policy could drop the “newest user message” follow-up
- Symptom: if user sends a message while a run is `running` (policy = `queue`), the queued run for
  the newer user message could be canceled when the previous run’s assistant message arrives “late”.
- Fix:
  - Tag scheduler-created runs with `debug.round_id` (`schedule_speaker.rb`)
  - Ignore “late message from previous round” in `AdvanceTurn` (`advance_turn.rb`)
- Files:
  - `playground/app/services/turn_scheduler/commands/schedule_speaker.rb`
  - `playground/app/services/turn_scheduler/commands/advance_turn.rb`
- Test:
  - `playground/test/services/turn_scheduler_input_policy_test.rb` (new test: “late previous AI message…”)

### TS-002 (P0) StartRound lacked `conversation.with_lock`
- Fix: wrap `StartRound#call` in `conversation.with_lock` to prevent concurrent “double round start”.
- File: `playground/app/services/turn_scheduler/commands/start_round.rb`

### TS-003 (P1) Group queue partial could crash due to wrong variable
- Fix: use `presenter.scheduling_state`.
- File: `playground/app/views/messages/_group_queue.html.erb`

### TS-004 (P1) Queue preview should respect mute/removal mid-round
- Fix: persisted preview filters with `can_be_scheduled?`.
- File: `playground/app/services/turn_scheduler/queries/queue_preview.rb`

### TS-005 (P1) Natural order “no self response” should also ban Copilot-generated user messages
- Fix: natural `banned_id` now bans the last speaker if it is an auto-responding participant
  (AI character OR Copilot full), not only assistant-role messages.
- File: `playground/app/services/turn_scheduler/queries/activated_queue.rb`

### TS-006 (P1) Test infra stability: add empty fixture for `conversation_runs`
- Fix: `playground/test/fixtures/conversation_runs.yml` (empty) to avoid FK validation failures when
  test DB has leftover `conversation_runs`.

### TS-101 (P0) Group `last_turn` regenerate now regenerates the whole “turn” (ST/Risu-aligned)
- Fix: `last_turn` regenerate now starts a new TurnScheduler round using `ActivatedQueue` semantics
  (multi-speaker for `reply_order=list/natural`, single-speaker for `pooled/manual`).
- Implementation:
  - Cancel running generation (request_cancel) before deleting messages
  - After deletion / fallback branch: `TurnScheduler::Commands::StartRound` with
    `trigger_message = conversation.last_user_message` and `is_user_input: false`
- Files:
  - `playground/app/controllers/conversations_controller.rb`
- Tests:
  - `playground/test/controllers/conversations_controller_test.rb`

### TS-102 (P0) Failed runs no longer leave “ghost ai_generating” scheduling state (UI unlock drift)
- Fix: when a run ends `failed`/`canceled` and there are **no active runs** left, reset conversation
  scheduling state to `idle` and broadcast a queue update (for all spaces).
- Files:
  - `playground/app/services/conversations/run_executor/run_persistence.rb`
  - `playground/app/models/conversation.rb`
- Tests:
  - `playground/test/services/conversations/run_executor_test.rb` (new: failure normalization)

### TS-103 (P0) `user_turn_debounce_ms` is now implemented for user-triggered rounds
- Fix: when a round is started from real user input, the first scheduled AI run is delayed by
  `spaces.user_turn_debounce_ms` (run_after = now + debounce). Subsequent user messages naturally
  cancel/replace the queued run via existing input handling.
- Files:
  - `playground/app/services/turn_scheduler/commands/start_round.rb`
  - `playground/app/services/turn_scheduler/commands/schedule_speaker.rb`
- Tests:
  - `playground/test/services/turn_scheduler/commands/start_round_test.rb`
  - `playground/test/services/turn_scheduler_debounce_test.rb`

### TS-104 (P0) Typing indicator no longer starts early for delayed runs
- Fix: `ScheduleSpeaker` no longer broadcasts typing immediately on run creation; typing now starts
  when execution begins (RunExecutor), avoiding “typing during debounce/delay”.
- File:
  - `playground/app/services/turn_scheduler/commands/schedule_speaker.rb`

### TS-201 (P1) `NextSpeaker` now delegates to `ActivatedQueue` (single source of truth)
- Fix: `NextSpeaker` no longer re-implements natural/pooled activation logic; it now delegates to
  `ActivatedQueue` and returns the first activated speaker.
- Cleanup: removed unused `RunPlanner.plan_user_turn!` (no longer needed after TS-101).
- Files:
  - `playground/app/services/turn_scheduler/queries/next_speaker.rb`
  - `playground/app/services/conversations/run_planner.rb`

### TS-203 (P1) Scheduler state machine drift cleanup
- Fixes:
  - Removed unused `round_active` state (not set by the scheduler)
  - `StopRound` now clears round state via `Conversation#reset_scheduling!`
  - Updated docs to match the canonical state set
- Files:
  - `playground/app/services/turn_scheduler.rb`
  - `playground/app/models/conversation.rb`
  - `playground/app/services/turn_scheduler/commands/stop_round.rb`
  - `docs/playground/CONVERSATION_AUTO_RESPONSE.md`

### TS-204 (P1) Delete disabled/broken `StaleRunsCleanupJob`
- Fix: removed `StaleRunsCleanupJob` and updated recurring jobs config/docs to reflect the per-run
  `ConversationRunReaperJob` safety net.
- Files:
  - `playground/config/recurring.yml`
  - `docs/playground/FRONTEND_TEST_CHECKLIST.md`

### TS-205 (P1) JSON queue updates now include a monotonic revision
- Fix: include `group_queue_revision` in `conversation_queue_updated` payload and ignore stale revisions
  client-side to reduce multi-process out-of-order UI lock flicker.
- Files:
  - `playground/app/services/turn_scheduler/broadcasts.rb`
  - `playground/app/javascript/controllers/conversation_channel_controller.js`

### TS-202 (P1) Remove dead/unused human-turn scheduling subsystem
- Decision: keep TurnScheduler queue **AI-only** (AI characters + Copilot full), ST/Risu-aligned; pure humans are triggers, not scheduled participants.
- Fixes:
  - Deleted `HumanTurnTimeoutJob` and `TurnScheduler::Commands::SkipHumanTurn`
  - `ScheduleSpeaker` no longer creates `human_turn` runs / timeout jobs
  - Removed dead UI/filtering paths for `human_turn` runs
  - Removed unused `skip_to_ai` parameter from `TurnScheduler.start_round!` / `StartRound`
- Files:
  - `playground/app/services/turn_scheduler.rb`
  - `playground/app/services/turn_scheduler/commands/start_round.rb`
  - `playground/app/services/turn_scheduler/commands/schedule_speaker.rb`
  - `playground/app/controllers/conversations_controller.rb`
  - `playground/app/presenters/group_queue_presenter.rb`
  - `playground/app/views/messages/_group_queue.html.erb`
  - `playground/app/views/conversations/_runs_panel.html.erb`
  - `playground/app/javascript/controllers/index.js`
  - `docs/playground/CONVERSATION_AUTO_RESPONSE.md`
  - `docs/playground/CONVERSATION_RUN.md`
  - `docs/playground/FRONTEND_TEST_CHECKLIST.md`
  - `docs/spec/SILLYTAVERN_DIVERGENCES.md`

### TS-301 (P2) Query perf & caching review
- Fixes:
  - Added opt-in profiling logs (`TURN_SCHEDULER_PROFILE=1`) for TurnScheduler hot paths
  - Avoid repeated `Space#group?` work inside `Broadcasts.queue_updated`
  - Avoid loading previous speaker association in `QueuePreview`
  - Make `Space#group?` cheaper (bounded COUNT)
- Files:
  - `playground/app/services/turn_scheduler/instrumentation.rb`
  - `playground/app/services/turn_scheduler/broadcasts.rb`
  - `playground/app/services/turn_scheduler/queries/activated_queue.rb`
  - `playground/app/services/turn_scheduler/queries/queue_preview.rb`
  - `playground/app/models/space.rb`

### TS-302 (P2) Documentation cleanup & cross-linking
- Fix: ensure scheduler-related docs match the code and explicitly document intentional differences vs ST/Risu.
- Files:
  - `docs/playground/CONVERSATION_RUN.md`
  - `docs/playground/FRONTEND_TEST_CHECKLIST.md`
  - `docs/playground/CONVERSATION_AUTO_RESPONSE.md`
  - `docs/spec/SILLYTAVERN_DIVERGENCES.md`

---

## 2) Remaining Issues & Remediation Plan (Prioritized)

Legend:
- **P0** = correctness / “could break chats or lose replies”
- **P1** = alignment / maintainability / prevents future regressions
- **P2** = perf / UX polish / cleanup that can wait

### P0: Correctness / user-visible brokenness

✅ All P0 items (TS-101..TS-104) are now fixed.

---

### P2: Perf + polish (do after correctness is stable)
✅ All P2 items (TS-301..TS-302) are now fixed.

---

## 3) Execution Strategy (How we will work through this)

1) P0 fixes only (TS-101..TS-104) + add tests per issue.
2) P1 refactors + dead code cleanup (TS-201..TS-205), keeping behavior stable.
3) P2 perf/doc polish.

For each task:
- Add/adjust automated tests first when possible.
- Implement change.
- Run `cd playground && bin/rails test` (and system tests if touched).
- Update docs in the same PR-sized change to prevent drift.

---

## 4) Re-Audit Checklist (Original Acceptance Criteria)

### Turn order correctness
- [x] mid-round: toggling Auto mode / Copilot does not corrupt order
- [x] user interjections: reject/queue/restart behave as documented, no dropped replies
- [x] membership mute/remove mid-round: skipped cleanly, UI preview correct
- [x] group: natural/list/pooled/manual match ST/Risu semantics

### No stuck states
- [x] worker crash / network hang: reaper + UI recovery work
- [x] run failure: UI shows actionable recovery and no “false locked” state

### Multi-process UI ordering safety
- [x] group queue Turbo updates are monotonic (guarded)
- [x] JSON state updates do not regress UI lock state

### Test coverage
- [x] edge cases have unit coverage
- [x] critical flows have system test coverage
- [x] scheduler-related checklist items are backed by real tests (or corrected)

### Cleanup & simplification
- [x] dead code removed or made reachable with tests
- [x] DB columns and docs reflect reality
