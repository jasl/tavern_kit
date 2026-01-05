# Backlogs

Low-priority future tasks and feature ideas. Items here are not committed to any timeline but are documented for future consideration.

---

## Chat Hotkeys (SillyTavern-like)

**Priority:** Low  
**Reference:** SillyTavern HotKeys

Implement SillyTavern-like chat hotkeys (minimal set) using Stimulus.

### Reference Behavior (ST)

- `Up`: edit last message
- `Ctrl+Up`: edit last USER message
- `Left/Right`: swipe left/right (disabled when chatbar has typed text)
- `Ctrl+Enter`: regenerate last AI response
- `Alt+Enter`: continue last AI response
- `Escape`: stop generation immediately (or close edit box if editing)

### Implementation Steps

1. Locate existing chat input Stimulus controller (`message_form_controller`, `chat_hotkeys_controller`, etc).
2. Implement keydown handler on the conversation container, with focus checks:
   - Ignore if target is not in the conversation page.
   - If typing in input/textarea:
     - Left/Right should not trigger swipes when textarea has content.
3. Implement actions:
   - **edit last message**: open inline editor for tail message (or navigate to edit route).
   - **edit last USER message**: find last message with role=user.
   - **swipe left/right**: call existing swipe endpoint for tail assistant message.
   - **regenerate**: call existing regenerate endpoint for tail assistant.
   - **continue**: add a new run kind=continue that appends continuation to tail assistant or creates a new assistant message (choose consistent semantics).
   - **escape**: call stop endpoint that requests cancel on running run.
4. Add a minimal stop endpoint:
   - `POST /conversations/:id/stop` → request_cancel on running run.
5. Add docs and tooltips: show hotkeys in UI / help dialog.

### Acceptance Criteria

- All hotkeys work; swipe hotkeys do nothing when textarea has typed content.
- Escape stops streaming immediately.
- No conflict with IME; only triggers on keydown when appropriate.

---

## Disable Auto-Mode on Typing

**Priority:** Low  
**Reference:** SillyTavern Group Chat

Implement "disable auto-mode on typing" behavior (configurable).

### Reference Behavior (ST)

When user starts typing into the send message textarea, auto-mode will be disabled, but already queued generations are not stopped automatically.

### Implementation Steps

1. Add a Space setting: `auto_mode_disable_on_typing` (boolean, default true).
2. Frontend:
   - On textarea input event, if auto-mode enabled and setting is true:
     - send PATCH to disable auto-mode (space or conversation setting depending on your model)
     - update UI toggle state immediately (optimistic UI ok).
3. Backend:
   - Provide a route: `PATCH /spaces/:id/auto_mode` (or update space settings).
   - Only writable by active human membership.
4. Confirm no cancellation:
   - Do NOT cancel running or queued runs; only stop planning future auto-mode runs.
5. Docs:
   - Document this behavior and how it differs from `during_generation_user_input_policy`.

### Acceptance Criteria

- Auto-mode turns off as soon as the user starts typing.
- Already queued generation still runs unless separately canceled.

---

## Conversation Export (JSONL and TXT)

**Priority:** Low  
**Reference:** SillyTavern Export

Add conversation export: JSONL (re-importable) and TXT (readable).

### Reference Behavior (ST)

- **Export as .jsonl**: re-importable, includes metadata (excluding images/attachments)
- **Export as .txt**: simplified text-only, cannot be re-imported

### Implementation Steps

1. Routes:
   - `GET /conversations/:id/export.jsonl`
   - `GET /conversations/:id/export.txt`
2. JSONL content:
   - conversation metadata (space settings snapshot, authors_note, root/parent/forked_from)
   - messages ordered by seq, including:
     - role, content (active swipe), excluded flag
     - all swipes (optional but recommended)
3. TXT content:
   - Render as readable transcript with timestamps and speaker names.
4. Authorization:
   - Only active members can export.
5. Tests:
   - Request spec: JSONL returns correct content-type and includes messages.
   - TXT returns plaintext and includes a readable transcript.

### Acceptance Criteria

- Users can back up or share RP logs.
- JSONL can be used later for import without losing critical metadata.
