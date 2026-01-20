# Playground Documentation Index

This directory contains comprehensive documentation for the **Playground** Rails application.

---

## Getting Started

**Start here if you're new to Playground development:**

1. **[../AGENTS.md](../AGENTS.md)** — AI agent guidelines (must-read for Claude/GPT)
2. **[PLAYGROUND_ARCHITECTURE.md](PLAYGROUND_ARCHITECTURE.md)** — Core architecture overview
3. **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** — Production deployment guide

---

## Core Architecture

### Data Models & Services

- **[PLAYGROUND_ARCHITECTURE.md](PLAYGROUND_ARCHITECTURE.md)** — Overall architecture, data models, service layers
- **[SPACE_CONVERSATION_ARCHITECTURE.md](SPACE_CONVERSATION_ARCHITECTURE.md)** — Space/Conversation separation and design

### Conversation System

- **[CONVERSATION_RUN.md](CONVERSATION_RUN.md)** — Run state machine, scheduling, concurrency
- **[CONVERSATION_AUTO_RESPONSE.md](CONVERSATION_AUTO_RESPONSE.md)** — Auto-reply mechanisms and policies
- **[BRANCHING_AND_THREADS.md](BRANCHING_AND_THREADS.md)** — Conversation branching and threads
- **[MESSAGE_VISIBILITY_AND_SOFT_DELETE.md](MESSAGE_VISIBILITY_AND_SOFT_DELETE.md)** — Message visibility (normal/excluded/hidden) and soft delete scheduler safety

### Settings & Prompt Building

- **[CONVERSATION_SETTINGS_PROMPT_BUILDER_INTEGRATION.md](CONVERSATION_SETTINGS_PROMPT_BUILDER_INTEGRATION.md)** — Settings schema + TavernKit integration

---

## Frontend Development

- **[FRONTEND_BEST_PRACTICES.md](FRONTEND_BEST_PRACTICES.md)** — Frontend patterns, Turbo, Stimulus
- **[FRONTEND_TEST_CHECKLIST.md](FRONTEND_TEST_CHECKLIST.md)** — Frontend testing checklist

---

## Performance & Profiling

- **[TURN_SCHEDULER_PROFILING.md](TURN_SCHEDULER_PROFILING.md)** — Turn scheduler performance analysis

---

## Project Management

- **[ROADMAP.md](ROADMAP.md)** — Feature roadmap and development phases
- **[BACKLOGS.md](BACKLOGS.md)** — Current backlog items

---

## Deployment

- **[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)** — Production deployment checklist

---

## Document Categories

### Architecture (Must Read)
- PLAYGROUND_ARCHITECTURE.md
- SPACE_CONVERSATION_ARCHITECTURE.md
- CONVERSATION_RUN.md

### Features (Read When Working On)
- CONVERSATION_AUTO_RESPONSE.md
- BRANCHING_AND_THREADS.md
- CONVERSATION_SETTINGS_PROMPT_BUILDER_INTEGRATION.md

### Frontend (For UI Work)
- FRONTEND_BEST_PRACTICES.md
- FRONTEND_TEST_CHECKLIST.md

### Operations (For Deployment)
- DEPLOYMENT_CHECKLIST.md

### Planning (For Product Work)
- ROADMAP.md
- BACKLOGS.md

---

## Quick Reference

### Common Patterns

**Namespaced Controllers:**
```ruby
# Always inherit from namespace ApplicationController
class Playgrounds::FooController < Playgrounds::ApplicationController
  # @space is already loaded
end
```

**Service Objects:**
```ruby
# app/services/conversations/run_planner.rb
module Conversations
  class RunPlanner
    def initialize(conversation)
      @conversation = conversation
    end
  end
end
```

**Real-time Streaming:**
```ruby
# Stream to typing indicator (ephemeral)
ConversationChannel.broadcast_stream_chunk(@conversation, chunk)

# Final message (persistent, triggers Turbo Stream)
Message.create!(content: content)
```

### Key Constraints

1. **No placeholder messages** — Create messages AFTER generation
2. **LLM calls in jobs** — Never call LLM APIs in controllers/models
3. **Single running run** — Max 1 running run per conversation
4. **Atomic swipe creation** — Create swipe with message atomically

### Testing

```bash
bin/rails test              # All tests
bin/rails test:system       # System tests
bin/ci                      # CI checks (tests + linters)
```

---

## Contributing

When adding new documentation:

1. Add entry to this README.md
2. Follow existing document structure
3. Use clear headings and code examples
4. Link to related documents
5. Update `../AGENTS.md` if adding critical patterns

---

## External References

- **TavernKit Gem Docs**: `../docs/` (gem-level documentation)
- **Root AGENTS.md**: `../AGENTS.md` (gem development guidelines)
