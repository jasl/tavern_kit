# Tavern

A production-grade **SillyTavern-inspired AI chat platform** built with Rails 8.2, showcasing the full capabilities of the [TavernKit](https://github.com/jasl/tavern_kit) gem.

**Playground** is both a complete LLM chat application and a comprehensive reference implementation for integrating TavernKit into Rails applications.

---

## Features

### Core Capabilities

- **Multi-Character Conversations** — Create roleplay spaces with multiple AI characters
- **Real-time Streaming** — Server-sent events for live AI response generation
- **Character Cards V2/V3** — Full support for SillyTavern character format
- **World Info / Lorebooks** — Context-aware knowledge injection with advanced triggers
- **Prompt Engineering** — Sophisticated prompt builder with TavernKit integration
- **Message Swipes** — Generate and switch between multiple AI response versions
- **Conversation Branching** — Branch conversations from any message point
- **Auto-Response Mode** — Automatic AI-to-AI conversations with configurable delays
- **Copilot Mode** — AI-assisted follow-up conversations (Full/None)
- **Advanced Settings** — Per-character LLM provider overrides, temperature, sampling, etc.

### Technical Highlights

- **Rails 8.2** — Modern Rails with Solid Queue, Solid Cable, Solid Cache
- **PostgreSQL 18 + pgvector** — Vector similarity search ready
- **Hotwire Stack** — Turbo + Stimulus for reactive UI without heavy JavaScript
- **ActionCable** — Real-time WebSocket communication for streaming
- **Tailwind CSS 4 + DaisyUI 5** — Modern, responsive UI design
- **Bun** — Fast JavaScript bundler and package manager
- **Multiple LLM Providers** — OpenAI, Anthropic, Google, Mistral, xAI, and more

---

## Quick Start

### Prerequisites

- **Ruby 3.4.0+**
- **PostgreSQL 18** (with pgvector extension)
- **Bun** ([installation guide](https://bun.sh/docs/installation))

### Installation

```bash
cd playground

# Install dependencies and setup database
bin/setup

# Start the development server
bin/dev
```

This starts four processes via foreman:
1. **web** — Rails server (Puma, http://localhost:3000)
2. **job** — SolidQueue worker (background jobs)
3. **js** — Bun JavaScript bundler (watch mode)
4. **css** — Tailwind CSS compiler (watch mode)

### First Run

On first launch, you'll be guided through the setup wizard:

1. Create administrator account
2. Configure LLM provider (OpenAI, Anthropic, etc.)
3. Import or create your first character
4. Start chatting!

---

## Documentation

**Start here if you're new to Playground development:**

- **[AGENTS.md](AGENTS.md)** — AI agent development guidelines (must-read for Claude/GPT)
- **[docs/PLAYGROUND_ARCHITECTURE.md](docs/PLAYGROUND_ARCHITECTURE.md)** — Core architecture overview
- **[docs/README.md](docs/README.md)** — Complete documentation index

### Key Concepts

- **Spaces** — Containers for conversations (e.g., solo roleplay playground)
- **Space Memberships** — Human users or AI characters in a space
- **Conversations** — Message timelines with branching support
- **Conversation Runs** — State machine for managing AI generation lifecycle
- **Messages & Swipes** — Messages with multiple AI-generated versions
- **Lorebooks** — Context-aware knowledge bases (Space + Conversation level)
- **Presets** — Prompt templates and generation settings

---

## Development

### Running Tests

```bash
bin/rails test              # All tests
bin/rails test:system       # System tests only
bin/ci                      # Full CI suite (tests + linters)
```

### Code Quality

```bash
bin/rubocop                 # Ruby style checks
bin/lint-eof --fix          # Fix end-of-file formatting
```

### Rebuilding Assets

```bash
bun run build               # JavaScript
bun run build:css           # Tailwind CSS
```

### Database Operations

```bash
bin/rails db:migrate        # Run migrations
bin/rails db:seed           # Seed sample data
bin/rails db:reset          # Reset database (drop + create + migrate + seed)
```

### Rails Console

```bash
bin/rails console           # Interactive Ruby console
```

---

## Architecture

### Data Model Hierarchy

```
User (authentication)
  └─> Space (STI: Playground / Discussion)
      └─> SpaceMembership (human / character)
          └─> Conversation
              ├─> Message
              │   └─> MessageSwipe (multiple versions)
              └─> ConversationRun (state machine: queued → running → succeeded)
```

### Service Layer

Playground follows a service-oriented architecture:

- **`PromptBuilding::*`** — TavernKit integration and prompt construction
- **`Conversations::*`** — Run planning, execution, and scheduling
- **`Messages::*`** — Message creation, deletion, and swipe management
- **`SpaceMemberships::*`** — Membership lifecycle and role management
- **`Presets::*`** — Preset application and snapshotting

### Real-time Architecture

```
User Action
    ↓
Controller enqueues ConversationRunJob
    ↓
Job executes → Stream chunks via ConversationChannel (ActionCable)
    ↓
Frontend displays typing indicator with real-time content
    ↓
On completion → Create Message → Turbo Stream broadcasts DOM update
```

**Key Design Principle**: No placeholder messages — streaming happens via ephemeral ActionCable events, final message created atomically on completion.

---

## Testing

### Test Categories

- **Unit Tests** — Models, services, helpers (`test/models/`, `test/services/`)
- **Controller Tests** — Request/response integration (`test/controllers/`)
- **System Tests** — End-to-end browser tests (`test/system/`)

### Frontend Testing Checklist

See [docs/FRONTEND_TEST_CHECKLIST.md](docs/FRONTEND_TEST_CHECKLIST.md) for comprehensive UI testing guidelines.

---

## Deployment

### Docker (via Kamal)

```bash
# Copy and configure deploy settings
cp config/deploy.yml.sample config/deploy.yml
vim config/deploy.yml

# Deploy to production
kamal setup          # First-time setup
kamal deploy         # Deploy/update
```

See [docs/DEPLOYMENT_CHECKLIST.md](docs/DEPLOYMENT_CHECKLIST.md) for production deployment guide.

### Environment Variables

Create `.env` file (see `.env.sample`):

```bash
# Database (required for production)
RAILS_DB_HOST=localhost
RAILS_DB_USERNAME=postgres
RAILS_DB_PASSWORD=your_password

# Secret keys (generate with: bin/rails secret)
SECRET_KEY_BASE=your_secret_key_base

# LLM Provider API Keys (optional, can configure via UI)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

---

## Contributing

### Workflow

1. Read [AGENTS.md](AGENTS.md) for development guidelines
2. Read relevant architecture docs in `docs/`
3. Write tests for your changes
4. Run `bin/ci` to ensure all checks pass
5. Submit pull request

### Code Style

- Follow Rails conventions and [Omakase RuboCop](https://github.com/rails/rubocop-rails-omakase/)
- Use service objects for complex business logic
- Keep controllers thin, models focused
- Write tests for all new features

---

## Tech Stack Details

| Component | Technology | Purpose |
|-----------|------------|---------|
| Framework | Rails 8.2 | Modern Rails with built-in Solid* stack |
| Database | PostgreSQL 18 | Primary database with pgvector |
| Queue | SolidQueue | Background job processing |
| Cache | SolidCache | Database-backed caching |
| Cable | SolidCable | Database-backed ActionCable |
| Server | Puma | Multi-threaded web server |
| Frontend | Turbo + Stimulus | Hotwire for reactive UI |
| CSS | Tailwind CSS 4 | Utility-first styling |
| UI Components | DaisyUI 5 | Pre-built component library |
| Icons | Iconify (Lucide) | Icon system via Tailwind plugin |
| JS Runtime | Bun | Fast JavaScript tooling |
| LLM Client | simple_inference | Streaming OpenAI-compatible API client |
| HTTP | httpx | Fiber-friendly HTTP client |

---

## 🗺 Roadmap

See [docs/ROADMAP.md](docs/ROADMAP.md) for feature roadmap and development phases.

### Current Status (Phase 3)

- ✅ Multi-character conversations
- ✅ Real-time streaming
- ✅ Character card V2/V3 support
- ✅ World Info / Lorebooks
- ✅ Message swipes & branching
- ✅ Auto-response mode
- ✅ Copilot mode
- ✅ Advanced prompt engineering

### Upcoming (Phase 4)

- 🔄 Memory system (short-term/long-term)
- 🔄 Vector search integration (pgvector)
- 🔄 RAG (Retrieval-Augmented Generation)
- 🔄 PWA support
- 🔄 Mobile-optimized UI

---

## Acknowledgments

- **[SillyTavern](https://github.com/SillyTavern/SillyTavern)** — The original inspiration
- **[Rails](https://rubyonrails.org/)** — The amazing web framework
- **[Hotwire](https://hotwired.dev/)** — Modern reactive UI patterns
- **[TavernKit](https://github.com/jasl/tavern_kit)** — The core prompt engineering gem

---

## Links

- **TavernKit Gem**: [github.com/jasl/tavern_kit](https://github.com/jasl/tavern_kit)
- **Documentation**: [docs/README.md](docs/README.md)
- **Architecture Guide**: [docs/PLAYGROUND_ARCHITECTURE.md](docs/PLAYGROUND_ARCHITECTURE.md)
- **Agent Guidelines**: [AGENTS.md](AGENTS.md)

---

## License

The MIT License (MIT)

Copyright (c) 2025 Jasl

See [MIT-LICENSE](MIT-LICENSE) for details.
