# Branching and Threads

This doc defines how `Conversation.kind` is used for **forking history (branch)** vs **parallel timelines (thread)**.

For the big-bang rewrite notes, see `docs/PLAYGROUND_REWRITE_CHANGELOG_2026-01-03.md`.

## Conversation kinds

- `root`: the primary timeline in a space.
- `branch`: a fork created by cloning history up to a message (SillyTavern-style).
- `thread`: a separate timeline “under” another conversation (Discord-style).

All conversations belong to a space, so permissions/participants come from the space.

## Branching (ST-style clone-to-point)

Branching is implemented as “clone the prefix and switch to it”.

Endpoint:

- `POST /conversations/:id/branch_from_message` with `message_id=...`

Rules:

- Only allowed for **solo** spaces (`space.kind == "solo"`). Non-solo returns `422`.

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
- the thread’s `space_id` matches the parent’s `space_id`

Meaning:

- Threads inherit the parent’s **space permissions** (same memberships and authorization rules).
- Threads do not imply history cloning; they are just another conversation timeline in the same space.
