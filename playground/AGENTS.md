# AI Agent Guidelines for Playground (Rails Application)

This document provides guidelines for AI assistants working on the **Playground** Rails application.

> **Note**: This is the demo Rails application. For the **TavernKit gem** guidelines, see `../AGENTS.md` in the root directory.

---

## Project Overview

**Playground** is a Rails 8.2 application demonstrating TavernKit's capabilities through an AI chat product. It's a SillyTavern-inspired conversational AI platform with real-time streaming, multi-character support, and advanced prompt engineering.

**Purpose**: Demo/reference implementation showcasing TavernKit gem integration in a production-grade Rails application.

---

## Key Documentation

**Read these FIRST when working on features:**

- `docs/PLAYGROUND_ARCHITECTURE.md` — Core architecture, data models, service layers
- `docs/CONVERSATION_RUN.md` — Run state machine and scheduling
- `docs/CONVERSATION_AUTO_RESPONSE.md` — Auto-reply mechanisms
- `docs/SPACE_CONVERSATION_ARCHITECTURE.md` — Space/Conversation design
- `docs/CONVERSATION_SETTINGS_PROMPT_BUILDER_INTEGRATION.md` — Settings schema integration
- `docs/BRANCHING_AND_THREADS.md` — Conversation branching
- `docs/FRONTEND_BEST_PRACTICES.md` — Frontend patterns
- `docs/FRONTEND_TEST_CHECKLIST.md` — Frontend testing checklist

**Project Management:**
- `docs/ROADMAP.md` — Feature roadmap and phases
- `docs/BACKLOGS.md` — Current backlog items

---

## ⚠️ Critical Rules

### 1. Always Search Before Building

**Problem**: Agents frequently recreate existing services or use outdated names.

**Solution**: Before creating ANY new class, grep for similar patterns:

```bash
# Check service namespaces
grep -r "module PromptBuilding" app/
grep -r "module Conversations" app/
grep -r "module Messages" app/
grep -r "class Conversations::RunExecutor" app/

# Check existing patterns
grep -r "def next_speaker" app/
grep -r "class.*Selector" app/
```

**Service Namespaces (check these first):**
- `PromptBuilding::*` — Prompt rules + TavernKit adapters
- `Conversations::*` — Run planning/execution + branching
- `Messages::*` — Message creation/deletion/swipes
- `SpaceMemberships::*` / `Spaces::*` — Membership lifecycle
- `Presets::*` — Preset apply/snapshot

### 2. Always Read Architecture Docs

**Before refactoring**, read:
1. `docs/PLAYGROUND_ARCHITECTURE.md` — Overall design
2. Relevant feature doc (e.g., `CONVERSATION_RUN.md` for run changes)

**Never "guess" architecture** — Rails apps have non-obvious domain logic.

### 3. Run CI Before Finishing

```bash
cd playground
bin/ci  # Runs tests, linters, etc.
```

If CI fails, **fix it before completing the task**.

### 4. File Formatting

- **All files must end with exactly ONE newline** (no trailing blank lines)
- Run `ruby bin/lint-eof --fix` before finishing

---

## Tech Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Framework | Rails 8.2 | Server-rendered, minimal JS |
| Ruby | 4.0.0 | Modern Ruby features |
| Database | PostgreSQL 18 + pgvector | Vector similarity search |
| Server | Puma | Rails 8.2 default, supports SolidQueue plugin |
| Realtime | ActionCable + SolidCable | Database-backed WebSocket |
| Jobs | SolidQueue | Built-in Rails 8 job backend |
| Cache | SolidCache | Built-in Rails 8 cache store |
| JS Runtime | Bun | Fast package manager + bundler |
| JS Build | Bun | No webpack/esbuild |
| CSS | Tailwind CSS 4 + DaisyUI 5 | Utility-first + components |
| Frontend | Turbo + Stimulus | Hotwire stack |
| Icons | Iconify (Lucide set) | `icon-[lucide--*]` classes |
| Animations | tailwindcss-motion | CSS-based animations |
| LLM Client | simple_inference + httpx | Streaming OpenAI-compatible APIs |

---

## Development Workflow

### Starting the Server

```bash
cd playground
bin/dev
```

This starts four processes via foreman:
1. `web` — Rails server (Puma, port 3000)
2. `job` — SolidQueue worker
3. `js` — Bun JS build (watch mode)
4. `css` — Tailwind CSS build (watch mode)

Access: `http://localhost:3000`

### Running Tests

```bash
bin/rails test              # All tests
bin/rails test test/models  # Model tests only
```

### CI Check

```bash
bin/ci  # Runs tests + linters
```

---

## Architecture Patterns

### 1. Namespaced Controllers (Required Pattern)

**Rule**: When creating controllers under a namespace, **MUST inherit from the namespace's ApplicationController**.

#### Why?

- Enforces access control at namespace level
- Loads shared resources (e.g., `@space`, `@conversation`)
- Prevents bypassing authorization

#### How?

**Step 1**: Create namespace ApplicationController (if not exists):

```ruby
# app/controllers/playgrounds/application_controller.rb
module Playgrounds
  class ApplicationController < ::ApplicationController
    include TrackedSpaceVisit  # Loads @space, enforces access
  end
end
```

**Step 2**: Inherit from namespace controller:

```ruby
# ✅ Correct
class Playgrounds::PromptPreviewsController < Playgrounds::ApplicationController
  def show
    # @space is already loaded and authorized
  end
end

# ❌ Wrong - bypasses namespace authorization
class Playgrounds::PromptPreviewsController < ApplicationController
end
```

**Existing namespace ApplicationControllers:**
- `Playgrounds::ApplicationController` — includes `TrackedSpaceVisit`
- `Conversations::ApplicationController` — loads `@conversation`
- `Settings::ApplicationController` — requires administrator role

### 2. Service Objects (Rails Service Layer)

Use service objects for complex business logic:

```ruby
# app/services/conversations/run_planner.rb
module Conversations
  class RunPlanner
    def initialize(conversation)
      @conversation = conversation
    end

    def plan_next_run
      # Complex run planning logic
    end
  end
end

# Usage in controller/job
Conversations::RunPlanner.new(@conversation).plan_next_run
```

**Service naming conventions:**
- `*Planner` — Planning/scheduling logic
- `*Executor` — Execution logic
- `*Selector` — Selection algorithms
- `*Builder` — Object construction
- `*Applier` — Apply changes

### 3. Real-time Communication Architecture

**Two separate channels** for different concerns:

```
ConversationChannel (JSON events)  → Ephemeral UI (typing indicator)
  - typing_start/typing_stop
  - stream_chunk
  - stream_complete
          ↓
[Generation completes]
          ↓
Turbo::StreamsChannel (DOM)        → Persistent UI (messages)
  - broadcast_append_to
  - broadcast_update_to
  - broadcast_remove_to
```

**Rules:**
1. **No placeholder messages** — Create messages AFTER generation completes
2. **Streaming to typing indicator** — Stream content to ephemeral UI
3. **Single JSON channel** — All JSON events through `ConversationChannel`
4. **Turbo Streams for final state** — Only use Turbo Streams for final DOM

**❌ Anti-pattern** (causes race conditions):

```ruby
@message = Message.create!(content: "")  # Placeholder
client.chat { |chunk| @message.broadcast_stream_chunk(chunk) }  # Race!
@message.save!
```

**✅ Correct pattern**:

```ruby
ConversationChannel.broadcast_typing_start(@conversation, membership: @speaker)
content = ""
client.chat { |chunk|
  content += chunk
  ConversationChannel.broadcast_stream_chunk(@conversation, chunk)
}
@message = Message.create!(content: content)  # Triggers Turbo Stream append
ConversationChannel.broadcast_typing_stop(@conversation)
```

### 4. Async I/O Constraints (Mandatory)

**All LLM API calls MUST run in ActiveJob**, not in controllers or models.

**Correct:**

```ruby
# app/jobs/conversation_run_job.rb
class ConversationRunJob < ApplicationJob
  def perform(run_id)
    run = ConversationRun.find(run_id)
    client = LLMClient.for(run.space)
    client.chat(messages: prompt) do |chunk|
      # Stream to ActionCable
    end
  end
end
```

**Wrong:**

```ruby
# app/controllers/conversations_controller.rb
def create_message
  client = LLMClient.for(@space)
  client.chat(messages: prompt) { }  # ❌ Blocking I/O in controller!
end
```

**Exception**: "Test Connection" button in Settings can call LLM directly (user-initiated, needs immediate feedback).

### 5. Run-Driven Scheduling

AI generation uses a state machine (`ConversationRun`):

**States:**
```
queued → running → succeeded / failed / canceled / skipped
```

**Key components:**
- `Conversations::RunPlanner` — Creates/updates queued runs
- `Conversations::RunExecutor` — Claims and executes runs
- `Conversations::SpeakerSelector` — Selects next speaker

**Concurrency guarantees** (via partial unique indexes):
- Max 1 `running` run per conversation
- Max 1 `queued` run per conversation

**Read**: `docs/CONVERSATION_RUN.md` for details.

### 6. Message Swipes (Multiple Response Versions)

Regenerate creates **new versions** instead of replacing:

- `MessageSwipe` model stores versions (position, content, metadata)
- `message.content` caches the active swipe
- Swipe switching: `POST /conversations/:id/messages/:message_id/swipe?dir=left|right`
- Selected swipe affects prompt context

**Read**: `docs/PLAYGROUND_ARCHITECTURE.md` for details.

---

## Frontend Guidelines

### Stimulus Controllers

**Creating a new controller:**

1. Create file: `app/javascript/controllers/foo_controller.js`
2. Register in `app/javascript/controllers/index.js`:
   ```js
   import FooController from "./foo_controller"
   application.register("foo", FooController)
   ```
3. Use in ERB:
   ```erb
   <div data-controller="foo" data-foo-target="container">
   ```

### DaisyUI Components

DaisyUI 5 is pre-configured. Use components directly:

```erb
<button class="btn btn-primary">Click me</button>
<div class="card bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">Card Title</h2>
  </div>
</div>
```

**Theme colors:**
- `btn-primary` — Primary action
- `btn-secondary` — Secondary action
- `btn-accent` — Accent action
- `btn-ghost` — Ghost button
- `btn-error` — Destructive action

### Icons (Lucide via Iconify)

Use Iconify Tailwind plugin with `lucide` prefix:

```erb
<span class="icon-[lucide--settings]"></span>
<span class="icon-[lucide--message-circle] text-2xl"></span>
<span class="icon-[lucide--trash] text-error"></span>
```

Browse icons: https://icon-sets.iconify.design/lucide/

### Tailwind Motion Animations

Use animation utilities from tailwindcss-motion:

```erb
<div class="motion-preset-fade-in">Fade in</div>
<div class="motion-preset-slide-in-bottom">Slide in</div>
```

---

## Common Tasks

### Adding a New Page

1. Create controller:
   ```bash
   bin/rails generate controller Playgrounds::Foo index
   ```

2. Edit route in `config/routes.rb`:
   ```ruby
   namespace :playgrounds do
     resources :foo, only: [:index]
   end
   ```

3. Create view: `app/views/playgrounds/foo/index.html.erb`

### Adding a New Service

1. Create file: `app/services/my_namespace/my_service.rb`
2. Add tests: `test/services/my_namespace/my_service_test.rb`
3. Use in controllers/jobs

### Adding a New Model

1. Generate migration:
   ```bash
   bin/rails generate model Thing name:string
   ```

2. Edit migration (add indexes, constraints, etc.)
3. Run migration: `bin/rails db:migrate`
4. Add tests: `test/models/thing_test.rb`

### Adding a Background Job

1. Create job:
   ```bash
   bin/rails generate job MyJob
   ```

2. Implement `perform` method
3. Enqueue: `MyJob.perform_later(args)`

### Rebuilding Assets

```bash
bun run build        # JS
bun run build:css    # CSS
```

### Installing JS Dependencies

```bash
bun add package-name
```

---

## Testing Guidelines

### Model Tests

```ruby
class MessageTest < ActiveSupport::TestCase
  test "creates swipe on initialization" do
    message = messages(:one)
    assert_equal 1, message.swipes.count
  end
end
```

### Controller Tests

```ruby
class ConversationsControllerTest < ActionDispatch::IntegrationTest
  test "creates conversation" do
    post conversations_url, params: { conversation: { title: "Test" } }
    assert_redirected_to conversation_path(Conversation.last)
  end
end
```

### Service Tests

```ruby
class RunPlannerTest < ActiveSupport::TestCase
  test "plans next run" do
    conversation = conversations(:one)
    planner = Conversations::RunPlanner.new(conversation)
    run = planner.plan_next_run
    assert_not_nil run
  end
end
```

---

## Code Style

### Ruby Conventions

- Follow standard Ruby style guide
- Use `frozen_string_literal: true`
- Prefer keyword arguments for clarity
- Use safe navigation (`&.`) when appropriate
- Use `||=` for memoization

### Rails Conventions

- Fat models, skinny controllers (but use services for complex logic)
- Use scopes for reusable queries
- Use concerns for shared behavior
- Use strong parameters in controllers

### Naming

- Models: singular (`Message`, `ConversationRun`)
- Controllers: plural (`MessagesController`)
- Services: descriptive nouns/verbs (`RunPlanner`, `SpeakerSelector`)
- Jobs: `*Job` suffix (`ConversationRunJob`)

---

## Debugging

### Rails Console

```bash
bin/rails console
```

### Logs

```bash
tail -f log/development.log
```

### Byebug

Add `debugger` anywhere in Ruby code:

```ruby
def my_method
  debugger  # Execution pauses here
  # ...
end
```

### ActionCable Logs

ActionCable events are logged to `log/development.log`. Look for:
- `[ActionCable]` prefix
- Channel subscriptions/unsubscriptions
- Broadcast events

---

## Performance

### N+1 Queries

Use `includes` to eager load associations:

```ruby
# ❌ N+1 query
@messages.each { |msg| puts msg.membership.name }

# ✅ Eager load
@messages.includes(:membership).each { |msg| puts msg.membership.name }
```

### Database Indexes

Always add indexes for foreign keys and frequently queried columns.

### Caching

Use Rails caching for expensive operations:

```ruby
Rails.cache.fetch("expensive_operation", expires_in: 1.hour) do
  # Expensive computation
end
```

---

## Troubleshooting

### Assets Not Updating

```bash
bin/rails tmp:clear
bun run build && bun run build:css
```

### ActionCable Not Working

1. Check WebSocket connection in browser DevTools
2. Verify cable.yml configuration
3. Check ActionCable logs

### Database Migrations Failing

```bash
bin/rails db:rollback
# Fix migration
bin/rails db:migrate
```

### Tests Failing

```bash
bin/rails db:test:prepare  # Reset test database
bin/rails test
```

---

## Security

### CSRF Protection

Rails automatically includes CSRF tokens. For Turbo forms:

```erb
<%= form_with model: @thing, data: { turbo: false } do |f| %>
  <!-- CSRF token automatically included -->
<% end %>
```

### Strong Parameters

Always use strong parameters in controllers:

```ruby
def conversation_params
  params.require(:conversation).permit(:title, :status)
end
```

### Authorization

Use authorization concerns:
- `TrackedSpaceVisit` — Loads and authorizes Space access
- `require_administrator` — Requires admin role

---

## Additional Resources

- **Rails Guides**: https://guides.rubyonrails.org/
- **Hotwire Docs**: https://hotwired.dev/
- **Tailwind CSS**: https://tailwindcss.com/
- **DaisyUI**: https://daisyui.com/
- **Stimulus**: https://stimulus.hotwired.dev/

---

## When to Read Parent Repo AGENTS.md

If you need to:
- Modify TavernKit gem code (in `lib/`)
- Understand prompt building internals
- Work on macro expansion
- Add new middleware to TavernKit

Read: `../AGENTS.md` (root repo guidelines for **gem development**)
