# AI Agent Guidelines for TavernKit

This document provides guidelines for AI assistants (Claude, GPT, Copilot, etc.) working on this codebase.

## Project Overview

TavernKit is a Ruby gem providing a SillyTavern-compatible LLM prompt building engine. It offers the same powerful prompt engineering features as SillyTavern (Prompt Manager, World Info, macros, Author's Note, etc.) in a clean, idiomatic Ruby API.

## Key Documentation

- `README.md` — Project overview and quick start
- `ROADMAP.md` — Development phases and feature plans
- `ARCHITECTURE.md` — Internal design, module responsibilities, data flow
- `docs/spec/TAVERNKIT_BEHAVIOR.md` — TavernKit behavior specification (ST compatible)
- `docs/spec/CONFORMANCE_RULES.yml` — Machine-readable conformance criteria

## ⚠️ Critical Rules

### 1. No Backward Compatibility (Pre-1.0)

This project follows [Semantic Versioning](https://semver.org/). Before v1.0.0:

- **Breaking changes are allowed** — Do not add compatibility shims
- **No deprecation warnings** — Remove old code directly
- **Refactor freely** — The API is not stable yet
- **Prefer clean APIs** — No migration paths needed

### 2. File Formatting

- **All files must end with exactly ONE newline** (no trailing blank lines)
- Run `ruby bin/lint-eof --fix` before finishing

### 3. No Warnings in Tests

- Code must produce zero warnings when running `bundle exec rake test`
- Fix all Ruby warnings (unused variables, etc.)

## 🎯 Ruby API Style (Vibe Coding)

**Always design APIs with the most idiomatic Ruby style.**

### Core Principles

#### 1. DSL-First Design

Prefer block-based DSL over method chaining or hash options:

```ruby
# ✅ Good: Block DSL
TavernKit.build(character: card) do
  preset my_preset
  message "Hello"
  before_build { |ctx| ctx.inject("note") }
end

# ❌ Avoid: Verbose hash-based API
TavernKit.build(character: card, preset: my_preset, message: "Hello", hooks: {...})
```

#### 2. Pipeline/Middleware Pattern

For multi-stage processing, use composable middleware:

```ruby
pipeline.insert_before(:compilation, MyCustomMiddleware)
pipeline.replace(:lore, CustomLoreEngine)
```

#### 3. Sensible Defaults, Full Customization

Work out of the box, but allow everything to be overridden:

```ruby
# Works with zero config
TavernKit.build(character: card, message: "Hi")

# Full control when needed
TavernKit.build(character: card, pipeline: custom_pipeline) do
  # ...
end
```

#### 4. Method Naming

- `build` — constructing objects
- `to_*` — conversions (`to_messages`, `to_hash`)
- `with` — immutable updates (`block.with(content: new_content)`)
- `?` suffix — predicates (`enabled?`, `pinned?`)

#### 5. Ruby Idioms

- Use `||=` for memoization
- Use `&.` safe navigation
- Use `Symbol#to_proc` (`items.map(&:name)`)
- Use keyword arguments for clarity
- Use blocks for callbacks and customization

#### 6. Composition Over Inheritance

Prefer small, focused classes composed together:

```ruby
class MyMiddleware < Middleware::Base
  def before(ctx)
    # modify context
  end
end
```

### Anti-Patterns to Avoid

- ❌ Java-style factory patterns with excessive indirection
- ❌ Deeply nested configuration hashes
- ❌ Stringly-typed APIs (use symbols)
- ❌ Mutable state without clear boundaries
- ❌ Overly defensive programming (trust internal code)

## Code Conventions

### Ruby Version

- Minimum Ruby 3.4.0
- Use modern Ruby features (pattern matching, endless methods where appropriate)

### Naming

- Classes: `CamelCase` (`CharacterCard::V2`)
- Methods/variables: `snake_case` (`build_main_prompt`)
- Constants: `SCREAMING_SNAKE_CASE` (`DEFAULT_MAIN_PROMPT`)
- Predicates: suffix with `?` (`prefer_char_prompt?`)

### Documentation

- Use YARD-style comments for public APIs
- Include `@param` and `@return` tags

## Testing

- Framework: Minitest (not RSpec)
- Run: `bundle exec rake test`
- Every new feature needs test coverage
- Test both happy path and error cases

## SillyTavern Compatibility

When implementing features, reference SillyTavern behavior:

- https://github.com/SillyTavern/SillyTavern
- https://docs.sillytavern.app/

Key ST concepts to preserve:

- Character Card V2/V3 spec compatibility
- Macro syntax: `{{char}}`, `{{user}}`, `{{original}}`
- Prompt ordering and injection positions
- World Info positions and evaluation order
- "Prefer Character" toggles

## Architecture Overview

### Data Flow

```
Character + Preset + User + History
           ↓
    Prompt::Pipeline (Middleware Chain)
           ↓
      Prompt::Plan
           ↓
    OpenAI Messages
```

### Core Components

- `TavernKit.build` — Main entry point (DSL)
- `Prompt::Pipeline` — Middleware orchestration
- `Prompt::Context` — State flowing through pipeline
- `Prompt::Middleware::*` — Individual processing stages
- `Prompt::Plan` — Final assembled prompt
- `Lore::Engine` — World Info evaluation

### Middleware Order

1. `Hooks` — before_build callbacks
2. `Lore` — World Info evaluation
3. `Entries` — Prompt entry processing
4. `PinnedGroups` — Build pinned content groups
5. `Injection` — In-chat injections
6. `Compilation` — Compile to blocks
7. `MacroExpansion` — Final macro pass
8. `PlanAssembly` — Assemble Plan
9. `Trimming` — Context window fitting

## Common Tasks

### Adding a New Macro

1. Add to `build_expander_vars` in `Middleware::Base`
2. Add test case
3. Document in README.md macro table

### Adding a New Middleware

1. Create class inheriting from `Middleware::Base`
2. Implement `before(ctx)` and/or `after(ctx)`
3. Register in `Pipeline.default`
4. Add tests

### Adding a Preset Option

1. Add `attr_reader` to `Preset`
2. Add to `initialize` with default
3. Use in relevant middleware
4. Add tests

## Error Handling

- Raise descriptive errors early (parse time, not runtime)
- Inherit from `TavernKit::Error`
- Use specific error classes per module

## Performance

- Avoid repeated regex compilation (use constants)
- Macro expansion happens multiple times — keep it efficient
- Token counting is performance-critical

## Playground (Demo Application)

The `playground/` directory contains a Rails 8.1 demo application for developing and testing LLM client features.

### Tech Stack

| Component | Technology |
|-----------|------------|
| Framework | Rails 8.1 (server-rendered) |
| Server | Falcon (Fiber-based, async) |
| Realtime | ActionCable Next + Async::Cable + SolidCable |
| JS Build | Bun |
| CSS | Tailwind CSS 4 + DaisyUI 5 |
| Frontend | Turbo + Stimulus |
| Icons | Iconify (Lucide) |
| Animations | tailwindcss-motion |
| LLM Client | simple_inference + httpx |

### Key Configuration

- **Fiber isolation**: `config.active_support.isolation_level = :fiber`
- **Async DB**: `config.active_record.async_query_executor = :fiber_pool`
- **CJK typography**: Full Chinese/Japanese/English support with proper fonts and text rendering

### Starting the Development Server

```bash
cd playground
bin/dev
```

This starts three processes via foreman:
1. `web` — Rails server (Falcon)
2. `js` — Bun JS build (watch mode)
3. `css` — Tailwind CSS build (watch mode)

Default port: `http://localhost:3000`

### Project Structure

```
playground/
├── app/
│   ├── assets/
│   │   ├── builds/          # Compiled JS/CSS (git-ignored)
│   │   └── stylesheets/
│   │       └── application.tailwind.css  # Tailwind entry point
│   ├── controllers/         # Rails controllers
│   ├── javascript/
│   │   ├── application.js   # JS entry point (Turbo + Stimulus)
│   │   └── controllers/     # Stimulus controllers
│   └── views/               # ERB templates
├── config/
│   └── routes.rb            # URL routing
├── bun.config.js            # Bun build configuration
├── package.json             # Node dependencies
├── Procfile.dev             # Development processes
└── bin/dev                  # Development startup script
```

### Development Guidelines

#### Adding New Pages

1. Create controller: `app/controllers/foo_controller.rb`
2. Create view: `app/views/foo/index.html.erb`
3. Add route in `config/routes.rb`

#### Namespaced Controllers (Required Pattern)

When creating controllers under a namespace (e.g., `Rooms`, `Settings`), you **MUST**:

1. **Create a namespace ApplicationController** if it doesn't exist:
   ```ruby
   # app/controllers/rooms/application_controller.rb
   module Rooms
     class ApplicationController < ::ApplicationController
       include RoomScoped  # Common concerns for this namespace
     end
   end
   ```

2. **Inherit from the namespace ApplicationController**, not the global one:
   ```ruby
   # ✅ Correct
   class Rooms::PromptPreviewsController < Rooms::ApplicationController
     # @room is already loaded and authorized
   end

   # ❌ Wrong - bypasses namespace authorization
   class Rooms::PromptPreviewsController < ApplicationController
   end
   ```

**Benefits**:
- Logic reuse (resource loading, access control)
- Clear boundaries prevent data leakage
- Authorization enforced at namespace level

**Existing namespace ApplicationControllers**:
- `Rooms::ApplicationController` — includes `RoomScoped` (loads `@room`)
- `Settings::ApplicationController` — requires administrator role

### Playground Best Practices

#### Real-time Communication: Avoiding Broadcast Race Conditions

When implementing features that involve both real-time streaming and DOM updates:

**Architecture** (ephemeral vs persistent separation):
```
RoomChannel (JSON events)          → Typing indicator (ephemeral UI)
  - typing_start/typing_stop
  - stream_chunk
  - stream_complete
          ↓
[Generation completes]
          ↓
Turbo::StreamsChannel (DOM)        → Final message (persistent)
  - broadcast_append
  - broadcast_update
  - broadcast_remove
```

**Rules**:
1. **Atomic message creation**: Create messages AFTER generation completes (no placeholder messages)
2. **Streaming to typing indicator**: Stream content to ephemeral UI, not message bubbles
3. **Single JSON channel per room**: All JSON events through `RoomChannel` to avoid timing issues
4. **Turbo Streams for final state**: Only use Turbo Streams for the final DOM mutation

**❌ Anti-pattern** (causes race conditions):
```ruby
@message = create_placeholder_message  # Empty content
client.chat { |chunk| @message.broadcast_stream_chunk(chunk) }  # Race!
@message.save!
```

**✅ Correct pattern**:
```ruby
broadcast_typing_start
content = generate_streaming(chunks_to: :typing_indicator)
@message = create_final_message(content)  # Triggers Turbo Stream append
broadcast_typing_stop
```

#### Typing Indicator Dynamic Styles

When broadcasting typing state, include styling information:

```ruby
RoomChannel.broadcast_typing(room, membership: speaker, active: true)
# Includes: membership_id, name, is_user, avatar_url, bubble_class
```

Frontend applies styles from the broadcast data (position, avatar, bubble color).

#### Message Swipes (Multiple AI Response Versions)

Regenerate uses **SillyTavern Swipes** strategy - creating new versions instead of replacing:

- `MessageSwipe` model stores multiple versions (position, content, metadata, room_run_id)
- `message.content` is a cache of the active swipe content
- Swipe switching: `POST /rooms/:room_id/messages/:message_id/swipe?dir=left|right`
- Selected swipe affects subsequent prompt context (used by PromptBuilder)
- Regenerate skips follow-ups to avoid unintended continuation

#### Async I/O Constraints (Mandatory)

**All LLM API calls MUST run in ActiveJob**, not in controllers or models:
- `RoomRunJob` — AI message generation
- `CopilotCandidateJob` — Copilot suggestions

**Exception**: "Test Connection" button in Settings can call LLM directly (user-initiated, has timeout, needs immediate feedback).

#### Run-Driven Scheduling

AI generation uses a state machine (`RoomRun`) with these states:
`queued` → `running` → `succeeded` / `failed` / `canceled` / `skipped`

Key components:
- `Room::RunPlanner` — Creates/updates queued runs
- `Room::RunExecutor` — Claims and executes runs
- `SpeakerSelector` — Selects next speaker based on `reply_order`

Concurrency guarantees (enforced by partial unique indexes):
- Max 1 `running` run per room
- Max 1 `queued` run per room (single-slot queue)

#### Adding Stimulus Controllers

1. Create controller: `app/javascript/controllers/foo_controller.js`
2. Register in `app/javascript/controllers/index.js`
3. Use in HTML: `<div data-controller="foo">`

#### Using DaisyUI Components

DaisyUI 5 is pre-configured. Use components directly:

```erb
<button class="btn btn-primary">Click me</button>
<div class="card bg-base-100 shadow-xl">...</div>
```

#### Using Icons (Lucide)

Use Iconify Tailwind plugin with `lucide` prefix:

```erb
<span class="icon-[lucide--settings]"></span>
<span class="icon-[lucide--message-circle]"></span>
```

#### Streaming Responses (LLM)

Use ActionCable for real-time streaming:

1. Create a channel for chat streaming
2. Use `simple_inference` gem for OpenAI-compatible APIs
3. Broadcast chunks via ActionCable as they arrive

### Testing the Playground

```bash
cd playground
bin/rails test
```

### Key Architecture Patterns

#### 1. Room Only Stores Config (Policy), Not Runtime State

- `Room` model contains settings and policies (reply_order, auto_mode_enabled, etc.)
- Runtime state lives in `room_runs` table (queued/running/succeeded/failed/canceled/skipped)
- Concurrency enforced via partial unique indexes: max 1 running, max 1 queued per room

#### 2. Atomic Message Creation

- Messages are created AFTER generation completes (no placeholder pattern)
- Streaming content displayed in typing indicator, not in message bubbles
- This eliminates race conditions between Turbo Streams and ActionCable events

#### 3. Settings Schema Pack Architecture

Settings use a modular JSON Schema system:

```
app/settings_schemas/
├── manifest.json           # Entry index
├── root.schema.json        # Root schema
├── defs/                   # Reusable definitions
│   ├── membership.schema.json
│   ├── room.schema.json
│   └── llm.schema.json
└── providers/              # Provider-specific schemas
    ├── openai.schema.json
    └── anthropic.schema.json
```

- `SettingsSchemaPack.bundle` returns dereferenced single JSON schema
- `FieldEnumerator` generates leaf fields for server-side rendering
- `x-ui.*` extensions control UI behavior (tab, group, order, quick, visibleWhen)

### Common Tasks

- **Rebuild assets**: `bun run build && bun run build:css`
- **Install new JS deps**: `bun add <package>`
- **Clear cache**: `bin/rails tmp:clear`
