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

### 4. Stay On Track (Avoid “Drift”)

When working in this repo, agents frequently go off-track by re-implementing existing components or using stale names. Follow this checklist:

- **Search before building**: before creating a new class/service, `grep` for similar names and patterns.
  - Playground service namespaces to check first:
    - `PromptBuilding::*` (prompt rules + adapters)
    - `Conversations::*` (run planning/execution + branching)
    - `Messages::*` (message creation/deletion/swipes)
    - `SpaceMemberships::*` / `Spaces::*` (membership lifecycle + space creation)
    - `Presets::*` (apply/snapshot)
- **Never “guess” architecture**: read `docs/playground/PLAYGROUND_ARCHITECTURE.md` and `ARCHITECTURE.md` before large refactors.
- **Always gate with CI**:
  - Playground changes: `cd playground && bin/ci`
  - Gem changes: `bundle exec rake test`

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

## Playground (Demo Rails Application)

The `playground/` directory contains a Rails 8.2 demo application showcasing TavernKit's capabilities.

**For detailed Playground development guidelines, see**: `playground/AGENTS.md`

---

**This section is a brief overview. The full Playground documentation lives in `playground/AGENTS.md`.**

### Quick Start

```bash
cd playground
bin/dev  # Starts Rails server + JS/CSS watchers
```

Access: `http://localhost:3000`

### Key Concepts

- **TavernKit integration**: Uses TavernKit gem for prompt building
- **Real-time streaming**: ActionCable for LLM response streaming
- **Multi-character**: Support for multiple AI characters in one conversation
- **Auto-reply**: AI→AI follow-up conversations
- **Message swipes**: Multiple response versions (SillyTavern-style)

For comprehensive documentation, see `playground/AGENTS.md`.
