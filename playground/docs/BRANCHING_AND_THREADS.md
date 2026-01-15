# Branching and Threads

This doc defines how `Conversation.kind` is used for **forking history (branch)** vs **parallel timelines (thread)**.

For the overall architecture, see `PLAYGROUND_ARCHITECTURE.md`.

## Conversation kinds

- `root`: the primary timeline in a space.
- `branch`: a fork created by cloning history up to a message (SillyTavern-style).
- `thread`: a separate timeline “under” another conversation (Discord-style).

All conversations belong to a space, so permissions/participants come from the space.

## Branching (ST-style clone-to-point)

Branching is implemented as "clone the prefix and switch to it".

Endpoint:

- `POST /conversations/:id/branch` with `message_id=...` in body

Rules:

- Only allowed for **Playground** spaces (`space.playground?`). Non-Playground returns `422`.

What gets created:

- `Conversation(kind: "branch")`
- `parent_conversation_id`: the source conversation
- `forked_from_message_id`: the message in the parent where the branch point occurs

What gets cloned:

- All messages where `seq <= forked_from_message.seq`
  - `seq` values are preserved
  - `message_swipes` are cloned (positions preserved)
  - `active_message_swipe` points to the cloned swipe, and `message.content` is synced to the active swipe content

Practical UX:

- To edit/regenerate earlier history without rewriting the current timeline: **create a branch first**, then edit/regenerate inside the branch.

## Threads (Discord-style)

Threads are a separate timeline anchored to a parent conversation:

- `Conversation(kind: "thread")` requires `parent_conversation_id`
- `forked_from_message_id` is blank for threads
- the thread's `space_id` matches the parent's `space_id`

Meaning:

- Threads inherit the parent's **space permissions** (same memberships and authorization rules).
- Threads do not imply history cloning; they are just another conversation timeline in the same space.

## Tail-Only Mutation Rule

**Invariant: Mutations are tail-only; non-tail requires branching.**

Any operation that modifies existing timeline content (edit, delete, regenerate, switch swipes) can only be performed on the tail (last) message. To modify earlier messages, use "Branch from here" to create a new timeline.

This rule is enforced consistently across the product:

| Operation | Tail Message | Non-Tail Message |
|-----------|--------------|------------------|
| Edit | Allowed | Blocked (use Branch) |
| Delete | Allowed | Blocked (use Branch) |
| Regenerate | Allowed | Auto-branches |
| Switch Swipe | Allowed | Blocked (use Branch) |

### Implementation

The `TailMutationGuard` service (`app/services/tail_mutation_guard.rb`) provides the central logic:

```ruby
guard = TailMutationGuard.new(conversation)
guard.tail?(message)    # => true/false
guard.tail_message_id   # => ID of the last message
```

Controllers use this service to enforce the rule:
- `MessagesController`: edit, inline_edit, update, destroy
- `SwipesController`: swipe navigation
- `ConversationsController`: regenerate (auto-branches for non-tail)

### UI Behavior

The frontend hides/disables mutation buttons for non-tail messages:

- **Edit/Delete buttons**: Hidden for non-tail user messages
- **Swipe navigation**: Hidden for non-tail assistant messages
- **Branch CTA**: Shown for non-tail user messages to provide a clear action path
- **Regenerate button**: Shows tooltip "Regenerate (creates branch)" for non-tail

The `message-actions` Stimulus controller reads `data-tail-message-id` from the DOM to determine button visibility, ensuring correct behavior even after Turbo broadcasts.

### Regenerate on Non-Last Assistant Message

When regenerating a message that is NOT the last assistant message:

- Automatically creates a branch (fork from target message)
- Redirects to the new branch
- Executes regenerate in the new branch
- Original conversation remains unchanged

This ensures the original timeline is preserved while allowing exploration of alternative responses.

### Swipe on Non-Last Message

When attempting to swipe (switch alternate versions) on a non-last message:

- Operation is blocked with a clear error message
- User is prompted that branching is required to switch swipes on earlier messages

This prevents inconsistent history where earlier messages reference content that no longer exists.

### Rationale

This design ensures **timeline consistency** — modifying history always preserves the original. Users who want to explore "what if" scenarios do so in branches, keeping the main conversation intact.

## Fork Point Protection

**Invariant: Fork point messages cannot be deleted or modified.**

A **fork point** is a message that is referenced by one or more child conversations via `forked_from_message_id`. Deleting or modifying a fork point would break the referential integrity of the conversation tree.

### Definition

A message is a fork point if:

```ruby
message.fork_point?  # => Conversation.where(forked_from_message_id: message.id).exists?
```

### Protection Rules

| Operation | Fork Point Message | Non-Fork Point Message |
|-----------|-------------------|------------------------|
| Edit | Blocked | Allowed (if tail) |
| Delete | Blocked | Allowed (if tail) |
| Group last_turn regenerate | Auto-branches | Deletes and regenerates |

### Implementation

1. **Model Layer** (`app/models/message.rb`):
   - `has_many :forked_conversations` uses `dependent: :restrict_with_error`
   - `fork_point?` method checks if any conversations reference this message

2. **Controller Layer** (`app/controllers/messages_controller.rb`):
   - `ensure_not_fork_point` before_action blocks edit/delete on fork points
   - Returns 422 with toast notification for turbo_stream requests
   - Returns redirect with alert for HTML requests

3. **Service Layer** (`app/services/messages/destroyer.rb`):
   - Returns `Result` object with error codes (`:fork_point_protected`, `:foreign_key_violation`)
   - Catches `ActiveRecord::RecordNotDestroyed` and `ActiveRecord::InvalidForeignKey`

4. **Group Regenerate** (`app/controllers/conversations_controller.rb`):
   - `handle_last_turn_regenerate` checks for fork points before deleting
   - If fork points exist: auto-branches from last user message, regenerates in branch
   - Original conversation and all its branches remain intact

### User Experience

When a user attempts to delete/edit a fork point message:

- **Toast notification**: "This message is a fork point for other conversations and cannot be modified."
- **Message remains unchanged**: No data loss or corruption

When group regenerate encounters fork points:

- **Auto-branch**: Creates a new branch from the last user message
- **Redirect**: User is taken to the new branch where regeneration proceeds
- **Original preserved**: The original conversation and its branches are untouched

### Rationale

Fork point protection ensures:

1. **Referential integrity**: Child conversations always have valid `forked_from_message_id` references
2. **No 500 errors**: FK violations are caught gracefully with user-friendly messages
3. **Predictable behavior**: Users understand why certain operations are blocked
4. **Non-destructive workflows**: Auto-branching provides an alternative path when direct modification is blocked
