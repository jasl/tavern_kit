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

---

## Advanced Sampler Parameters (SillyTavern Common Settings)

**Priority:** Low  
**Reference:** [SillyTavern Common Settings](https://docs.sillytavern.app/usage/common-settings/)

Implement additional sampler parameters from SillyTavern's Common Settings page. These are advanced generation parameters that control text sampling behavior.

### Currently Implemented

- `max_context_tokens` — Context (tokens)
- `max_response_tokens` — Response (tokens)
- `temperature` — Temperature
- `top_p` — Top P (nucleus sampling)
- `top_k` — Top K
- `repetition_penalty` — Repetition Penalty

### Repetition Penalty Extensions

| Parameter | Description |
|-----------|-------------|
| `repetition_penalty_range` | How many tokens from the last generated token will be considered for the repetition penalty. Set to 0 to disable. |
| `repetition_penalty_slope` | If both this and range are above 0, the repetition penalty will have a greater effect at the end of the prompt. Set to 0 to disable. |

### Additional Samplers

| Parameter | Description | Disable Value |
|-----------|-------------|---------------|
| `typical_p` | Prioritizes tokens based on their deviation from the average entropy. | 1 |
| `min_p` | Limits token pool by cutting off low-probability tokens relative to the top token. Works best at 0.01-0.1. | 0 |
| `top_a` | Sets a threshold based on the square of the highest token probability. | 0 |
| `tfs` (Tail Free Sampling) | Searches for a tail of low-probability tokens using derivatives. The closer to 0, the more discarded. | 1 |
| `smoothing_factor` | Increases likelihood of high-probability tokens using quadratic transformation. Works best without truncation samplers. | 0 |

### Dynamic Temperature

| Parameter | Description |
|-----------|-------------|
| `dynamic_temperature` | Scales temperature dynamically based on the likelihood of the top token. |
| `dynatemp_min` | Minimum temperature for dynamic temperature. |
| `dynatemp_max` | Maximum temperature for dynamic temperature. |
| `dynatemp_exponent` | Applies an exponential curve based on the top token. |

### Advanced Cutoffs

| Parameter | Description | Disable Value |
|-----------|-------------|---------------|
| `epsilon_cutoff` | Probability floor below which tokens are excluded. In units of 1e-4; reasonable value is 3. | 0 |
| `eta_cutoff` | Main parameter of Eta Sampling technique. In units of 1e-4; reasonable value is 3. | 0 |

### Repetition Prevention

| Parameter | Description |
|-----------|-------------|
| `dry_multiplier` | DRY repetition penalty multiplier. Penalizes tokens that would extend sequences that previously occurred. Set to 0 to disable. |
| `dry_base` | DRY base value. |
| `dry_allowed_length` | DRY allowed length before penalty applies. |
| `dry_sequence_breakers` | List of sequences that can repeat verbatim (e.g., names). |

### Exclude Top Choices (XTC)

| Parameter | Description |
|-----------|-------------|
| `xtc_probability` | Probability of applying XTC sampling. Set to 0 to disable. |
| `xtc_threshold` | Threshold for XTC sampling. |

### Mirostat

| Parameter | Description |
|-----------|-------------|
| `mirostat_mode` | 0 = disable, 1 = Mirostat 1.0 (llama.cpp only), 2 = Mirostat 2.0 |
| `mirostat_tau` | Target perplexity. |
| `mirostat_eta` | Learning rate. |

### Other

| Parameter | Description |
|-----------|-------------|
| `num_beams` | Beam search width. |
| `top_nsigma` | Filters logits based on standard deviations from the maximum logit value. |

### Implementation Notes

1. **Backend Support**: Many of these parameters are only supported by specific backends:
   - llama.cpp / KoboldCpp: Full support for most parameters
   - vLLM: Partial support
   - OpenAI / Anthropic APIs: Only basic parameters (temperature, top_p, max_tokens)

2. **Suggested Approach**:
   - Add parameters to `LLMSettings::LLM::GenerationSettings`
   - Add UI controls with appropriate ranges and defaults
   - Pass parameters to `LLMClient` only when supported by the provider
   - Consider adding provider capability flags (e.g., `supports_mirostat?`, `supports_dry?`)

3. **Priority Order** (based on common usage):
   - High: `min_p`, `typical_p`, `repetition_penalty_range`
   - Medium: `tfs`, `mirostat`, `dry_*`
   - Low: `top_a`, `epsilon_cutoff`, `eta_cutoff`, `xtc_*`, `top_nsigma`

### Acceptance Criteria

- Settings are configurable in the Space settings UI
- Parameters are passed to LLM API when supported by the provider
- Unsupported parameters are gracefully ignored (not sent to API)
- UI shows which parameters are supported by the current provider

---

## Chat-bound Lorebooks

**Status:** ✅ Backend implemented (UI pending)  
**Priority:** Low  
**Reference:** SillyTavern World Info ("Chat lore" feature)

Allow each conversation to have its own linked lorebook(s), independent of character or space-level lorebooks.

### Reference Behavior (ST)

In SillyTavern, each chat can have a dedicated lorebook attached. This is useful for:
- Per-scenario World Info (different locations, events for each chat)
- Conversation-specific context that shouldn't affect other chats
- Testing lorebook changes without affecting the main character

### Implementation Steps

1. **Model**:
   - Create `ConversationLorebook` join model (similar to `CharacterLorebook` and `SpaceLorebook`)
   - Fields: `conversation_id`, `lorebook_id`, `priority`, `enabled`
   - Add `has_many :conversation_lorebooks` to `Conversation`

2. **PromptBuilder Integration**:
   - Update `PromptBuilder#lore_books` to collect conversation-level lorebooks
   - Include as ST-style `source: :chat` (chat lore entries sort first in prompt)

3. **UI**:
   - Add "Linked Lorebooks" section in conversation settings modal
   - Allow attaching/detaching lorebooks per conversation

4. **Tests**:
   - Model tests for `ConversationLorebook`
   - PromptBuilder tests for conversation-level lorebook collection

### Acceptance Criteria

- Users can attach lorebooks to individual conversations
- Conversation lorebooks are included in prompt building
- Conversation lorebooks are not exported with the character

---

## Persona-bound Lorebooks

**Priority:** Low  
**Reference:** SillyTavern User Persona + World Info  
**Depends on:** Full Persona feature implementation

Allow user personas to have linked lorebooks, similar to character lorebooks.

### Reference Behavior (ST)

In SillyTavern, the user's "Persona" is essentially a user-side character card with:
- Name, description, personality
- Can link to World Info files (lorebooks)

When a persona is active, its linked lorebooks are included in prompt building.

### Prerequisites

This feature requires implementing a full Persona system first:
- `Persona` model (similar to `Character`) with fields: name, description, personality, avatar
- `PersonaLorebook` join model
- Persona selection UI in conversation/space settings
- Currently, Playground only has `SpaceMembership.persona` as a text field

### Implementation Steps

1. **Persona Model** (prerequisite):
   - Create `Persona` model with character-like fields
   - Migrate `SpaceMembership.persona` text to reference `Persona`
   - Add persona management UI

2. **PersonaLorebook Model**:
   - Create join model: `persona_id`, `lorebook_id`, `source`, `priority`, `enabled`
   - Similar structure to `CharacterLorebook`

3. **PromptBuilder Integration**:
   - Collect active persona's lorebooks
   - Insert appropriately based on `insertion_strategy`

4. **UI**:
   - Add "Linked Lorebooks" section to Persona edit page
   - Show persona lorebook status in conversation view

### Acceptance Criteria

- Users can create and manage personas with linked lorebooks
- Active persona's lorebooks are included in prompt building
- Persona lorebooks integrate with existing lorebook priority system
