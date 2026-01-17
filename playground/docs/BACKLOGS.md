# Backlogs

Low-priority future tasks and feature ideas. Items here are not committed to any timeline but are documented for future consideration.

---

## Lorebook Autocomplete for Character Links (Primary / Additional)

**Priority:** Low  
**Status:** Backlog

Character `extensions.world` / `extensions.extra_worlds` currently use a simple HTML `datalist` for suggestions, capped to **20** items to avoid rendering huge option lists when lorebooks scale up.

### Future Direction

- Replace `datalist` with a real autocomplete:
  - server-side search (query by prefix / fuzzy matching)
  - async fetch + debounced typing
  - show disambiguators for duplicate names (owner/system, visibility)

---

## Large Conversation Virtual List (DOM windowing)

**Priority:** Low  
**Status:** Backlog (moved from ROADMAP 2026-01-13)

If we hit performance bottlenecks with very long conversations, implement DOM windowing / virtual list for the message list.

### Notes

- Keep Turbo Stream append/prepend semantics intact (including catch-up fetches and history loading).
- Avoid breaking anchors, swipes, and per-message actions.

### Acceptance Criteria

- Smooth scrolling with 1000+ messages on mid-range devices.
- No regressions in Turbo Stream updates and message actions.

---

## Chat Hotkeys (SillyTavern-like) ✅ COMPLETED

**Priority:** Low  
**Reference:** SillyTavern HotKeys  
**Status:** ✅ Implemented (2026-01-10)

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

## Auto-mode Round Limits ✅ COMPLETED (替代 "Disable Auto-Mode on Typing")

**Priority:** Low  
**Reference:** SillyTavern Group Chat (intentional divergence)  
**Status:** ✅ Implemented (2026-01-10)

Implement conversation-level auto-mode with round limits to prevent runaway LLM costs.

### Divergence from ST

SillyTavern uses global `is_group_automode_enabled` with "disable on typing" behavior. TavernKit uses **conversation-level** auto-mode with explicit **round limits** (1-10, default 4).

See `docs/spec/SILLYTAVERN_DIVERGENCES.md` for detailed comparison.

### Implementation

1. **Database**: `conversations.auto_mode_remaining_rounds` (integer, nullable)
   - `null` = disabled
   - `> 0` = active, decrements each AI response
   - `0` = exhausted (auto-set to null)

2. **Backend**:
   - `POST /conversations/:id/toggle_auto_mode?rounds=N`
   - `Conversation#start_auto_mode!`, `#stop_auto_mode!`, `#decrement_auto_mode_rounds!`
   - `AutoModePlanner` checks conversation (not space) and decrements rounds

3. **Frontend**:
   - Auto toggle button in group chat toolbar (`_group_queue.html.erb`)
   - Shows Play/Pause with remaining rounds counter
   - `auto_mode_toggle_controller.js` for interactions

4. **Restrictions**:
   - Only available for group chats (`space.group?`)
   - Rounds clamped to 1-10 range

### Acceptance Criteria

- ✅ Start auto-mode from group toolbar with default 4 rounds
- ✅ Rounds decrement after each AI response
- ✅ Auto-disable when rounds reach 0
- ✅ Manual stop via Pause button
- ✅ Real-time UI updates via Turbo Streams
- ✅ Single playgrounds don't show auto-mode button

---

## Conversation Export (JSONL and TXT) ✅ COMPLETED

**Priority:** Low  
**Reference:** SillyTavern Export  
**Status:** ✅ Implemented (2026-01-10)

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
   - Similar structure to `SpaceLorebook` / `ConversationLorebook`

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

---

## SillyTavern/RisuAI Feature Gaps (TurnScheduler)

**Priority:** Low  
**Reference:** SillyTavern Group Chat, RisuAI Group Chat

The following features are supported in SillyTavern or RisuAI but not yet implemented in TavernKit's TurnScheduler. These are documented for future consideration.

### activation_regex

**Reference:** SillyTavern Group Chat Settings

ST supports activating specific characters via regex matching. When a message matches a character's `activation_regex`, that character is activated to speak regardless of the normal activation strategy.

**Use Case:** Trigger specific characters when certain keywords or patterns appear in messages.

**Implementation Notes:**
- Add `activation_regex` field to `SpaceMembership` or character settings
- Modify `TurnScheduler::Queries::ActivatedQueue` to check regex matches
- Consider using `js_regex_to_ruby` gem for ST-compatible regex syntax

### Custom Activation Script

**Reference:** SillyTavern Extensions API

ST allows JavaScript scripts to customize character activation logic, providing more flexible control than built-in strategies.

**Use Case:** Complex activation rules that can't be expressed with built-in strategies (natural, list, pooled, manual).

**Implementation Notes:**
- This would require a sandboxed script execution environment
- Consider a simpler approach: custom activation rules via configuration instead of scripts
- Low priority due to security and complexity concerns

### Response Timeout per Character

**Reference:** SillyTavern Group Settings

ST supports setting different response timeouts for each character. Currently, TavernKit uses a global `STALE_TIMEOUT` (10 minutes) for all characters.

**Use Case:** Some characters may need longer generation times (e.g., complex reasoning models) while others should respond quickly.

**Implementation Notes:**
- Add `response_timeout_seconds` field to `SpaceMembership`
- Modify `ConversationRunReaperJob` to use per-character timeout
- Update `ConversationRun#stale?` to accept custom timeout

### Chunked Generation (Continue)

**Reference:** SillyTavern Long Response Handling

ST supports "chunked generation" where long responses that exceed `max_tokens` are automatically continued. The AI generates in chunks until it naturally completes or hits a total limit.

**Use Case:** Generate very long responses (e.g., detailed stories, comprehensive explanations) without manual continuation.

**Implementation Notes:**
- Add `continue` run kind to `ConversationRun`
- Implement continuation logic in `RunExecutor` that detects incomplete responses
- Add `max_continuation_chunks` setting to prevent infinite loops
- Consider streaming continuation for better UX

---

## Token Usage - Advanced Features

**Priority:** Low  
**Status:** Backlog

Advanced token usage features for cost control and billing. Basic token statistics (Conversation, Space, User level) are already implemented.

### User Token Usage Dashboard

**Priority:** Low  
**Reference:** OpenAI/Anthropic Usage pages

Create a dedicated page showing user's token consumption history, similar to commercial LLM service usage pages.

**Implementation Notes:**
- New route: `GET /settings/usage` or `/account/usage`
- Display user's total token consumption across all owned Spaces
- Break down by Space with drill-down capability
- Time range filters (last 7 days, 30 days, all time)
- Chart visualization of usage over time
- Export usage data as CSV

**Acceptance Criteria:**
- Users can view their historical token usage
- Usage is broken down by Space
- Charts show usage trends over time

### Admin Token Usage Dashboard

**Priority:** Low

Global admin dashboard for monitoring system-wide token usage.

**Implementation Notes:**
- New admin route: `GET /admin/usage`
- Global statistics: total tokens, active users, active spaces
- Top users/spaces by token consumption
- Usage trends over time
- Cost estimation (requires configurable token pricing)
- Anomaly detection (sudden usage spikes)

**Acceptance Criteria:**
- Admins can monitor system-wide token usage
- Can identify high-usage users/spaces
- Basic cost analysis available
