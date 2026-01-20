# Space + Conversation Architecture (Playground)

This doc describes the **Space / Conversation / ConversationRun** split in the Rails app under `playground/`.

For the overall architecture, see `PLAYGROUND_ARCHITECTURE.md`.

## Orthogonal responsibilities

- **Space**: permissions, participants, and default policies/settings.
- **Conversation**: a single message timeline inside a space.
- **ConversationRun**: runtime execution state (queueing, running, cancelation, errors).

This separation is intentional: we do **not** store runtime scheduler state on Space/Conversation/Message.

## Core models and relationships

### Space (STI)

Base class that holds participant lists and default behavior knobs (reply order, auto-mode, debounce, etc.).

Uses **Single Table Inheritance (STI)** with two subclasses:

- `Spaces::Playground`: Solo roleplay (one human + AI characters). Primary space type for the Playground app.
- `Spaces::Discussion`: Multi-user chat (multiple humans + AI characters). Reserved for future use.

Key attributes and associations:

- `Space(type)` — STI discriminator (`Spaces::Playground` or `Spaces::Discussion`)
- `Space(owner_id)` — references the owning User
- `Space has_many :space_memberships`
- `Space has_many :conversations`

Type-checking methods: `space.playground?`, `space.discussion?`

### SpaceMembership

Represents a "participant identity" inside a space. Designed as an **author anchor** — memberships are never destroyed, preserving message author references.

- `SpaceMembership(kind: human|character)`
- `SpaceMembership(user_id)` for humans
- `SpaceMembership(character_id)` for AI characters
- `SpaceMembership(role, position, auto, auto_remaining_steps, settings)`

**Lifecycle (status enum):**
- `active`: Active member, can access the space
- `removed`: Left or kicked, cannot access but messages preserved

**Participation (participation enum):**
- `active`: Full participant, included in AI speaker selection
- `muted`: Not auto-selected, but visible and can be manually triggered
- `observer`: Watch only (reserved for future multi-user spaces)

**Removal tracking:**
- `removed_at`: When the membership was removed
- `removed_by_id`: User who performed the removal
- `removed_reason`: Optional reason string

**Key scopes:**
- `active`: `status = 'active'`
- `participating`: `status = 'active' AND participation = 'active'`
- `removed`: `status = 'removed'`

**Display behavior:**
- `membership.display_name` returns `"[Removed]"` for removed memberships
- Historical messages retain author references through the preserved membership record

### Conversation

Owns the message timeline (and only the timeline). Supports tree structure for branching.

- `Conversation(kind: root|branch|thread)`
- `Conversation(visibility: shared|private)`
- `Conversation belongs_to :space`
- `Conversation has_many :messages`
- `Conversation has_many :conversation_runs`

**Tree structure (for branching):**
- `parent_conversation_id`: Reference to parent conversation (nil for root)
- `root_conversation_id`: Reference to tree root (self-referential for root conversations)
- `forked_from_message_id`: The message at which this branch was created

**Associations:**
- `parent_conversation`: The parent in the tree
- `child_conversations`: Direct children
- `descendant_conversations`: All conversations sharing the same root

**Data invariants:**
- Root conversations: `root_conversation_id == id`
- Child conversations: `root_conversation_id` inherited from parent
- `forked_from_message` must belong to `parent_conversation`

### Message + MessageSwipe

Messages are authored by a `SpaceMembership` (not directly by User/Character).

- `Message belongs_to :conversation`
- `Message belongs_to :space_membership`
- `Message(seq)` provides deterministic ordering within a conversation (unique per conversation).
- `Message has_many :message_swipes`
- `Message belongs_to :active_message_swipe`
- `Message belongs_to :origin_message` (optional, for cloned messages in branches)

`MessageSwipe` stores alternate versions of the same message (used by regenerate).

**Generation status (`generation_status` column):**
- `nil`: User-sent message (not AI-generated)
- `"generating"`: AI is currently generating this message
- `"succeeded"`: Generation completed successfully
- `"failed"`: Generation failed with an error

This is a proper DB column (not `metadata["generating"]`), eliminating Turbo Stream race conditions.

**Branching support:**
- `origin_message_id`: References the original message this was cloned from (nil for original messages)
- When a conversation is branched, messages are cloned with their `seq` preserved
- All swipes are also cloned, with `active_message_swipe_id` pointing to the correct clone

### ConversationRun

Represents one unit of “AI work to do”.

- `ConversationRun(kind: auto_response|auto_user_response|regenerate|force_talk)`
- `ConversationRun(status: queued|running|succeeded|failed|canceled|skipped)`
- `ConversationRun(speaker_space_membership_id, run_after, cancel_requested_at, heartbeat_at, debug, error)`
- `ConversationRun(conversation_round_id: uuid?)` — nullable link to a TurnScheduler round (may be nullified by cleanup)

See `CONVERSATION_RUN.md` for the state machine and scheduling rules.

### ConversationRound + ConversationRoundParticipant

TurnScheduler persists round runtime state as a first-class entity:

- `ConversationRound(status: active|finished|superseded|canceled)`
- `ConversationRound(scheduling_state: ai_generating|paused|failed)` (meaningful only while `status=active`)
- `ConversationRound(current_position: integer)` (0-based cursor)
- `ConversationRoundParticipant(position, space_membership_id, status: pending|spoken|skipped)`

Key properties:
- The activated queue is computed once at round start and is never recalculated mid-round.
- Rounds are periodically cleaned up (keep recent 24h). `conversation_runs.conversation_round_id` uses `on_delete: :nullify`, so it must be treated as optional.

## Playground vs Discussion spaces (STI)

- **Playground** (`Spaces::Playground`, `space.playground?`): Solo roleplay with one human participant, plus zero or more AI characters.
  - Enforced at the model layer via validation — Playground spaces reject additional human memberships.
  - Conversation branching is only allowed in Playground spaces.
  - This is the primary (and currently only) space type used in the Playground web UI.

- **Discussion** (`Spaces::Discussion`, `space.discussion?`): Multi-user chat with multiple humans and AI characters.
  - Reserved for future implementation.
  - No single-human constraint.

Both types share the same primitives (memberships, conversations, runs); only constraints differ.

## Deterministic message ordering

Messages use `messages.seq` (`bigint`) as the stable ordering key:

- Unique index on `(conversation_id, seq)`
- When a message is created without an explicit `seq`, it is assigned inside a transaction as `max(seq) + 1`.

This makes “clone-to-point branching” and stable pagination straightforward.

## Real-time updates (no placeholder messages)

Playground separates **ephemeral streaming UI** from **persistent message records**:

- ActionCable (`ConversationChannel`) broadcasts JSON events for typing indicators and stream chunks.
- Turbo Streams broadcast final DOM mutations when a message is created or updated.
- The app does **not** rely on placeholder messages.
- Generation status is tracked via the `generation_status` column on `Message` (not metadata).

**Message delivery patterns:**
- **User messages**: Dual delivery for multi-user reliability
  - HTTP Turbo Stream response: Reliable delivery to sender (avoids WebSocket reconnection race conditions)
  - ActionCable broadcast: Delivery to other users in the conversation
  - Client-side deduplication in `conversation_channel_controller.js` prevents sender duplicates
- **AI messages**: Broadcast via ActionCable from `RunPersistence` after generation completes

## Conversation branching

Implements SillyTavern-style branching: "clone chat up to a message and switch to it".

### Forker service

`Conversations::Forker` is the single entry point for creating branches:

```ruby
result = Conversations::Forker.new(
  parent_conversation: conversation,
  fork_from_message: message,
  kind: "branch",
  title: "My Branch",       # optional, defaults to "Branch"
  visibility: "shared"      # optional, defaults to "shared"
).call
```

**Behavior:**
1. Validates that branching is only allowed in Playground spaces
2. Creates child conversation with correct tree structure fields
3. Clones messages up to `fork_from_message` (inclusive), preserving `seq`
4. Clones all swipes, setting `active_message_swipe_id` correctly
5. Returns the new child conversation

### Non-tail message protection (Timelines semantics)

To prevent inconsistent history when modifying non-last messages:

- **Regenerate on non-last message**: Auto-branches, then regenerates in the new branch
- **Swipe on non-last message**: Blocked with user-friendly alert

This aligns with SillyTavern Timelines extension behavior.
