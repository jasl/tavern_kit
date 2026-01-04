# TavernKit 🍺

A Ruby toolkit for building highly customizable LLM chat prompts, inspired by [SillyTavern](https://github.com/SillyTavern/SillyTavern).

**TavernKit** aims to bring the power of SillyTavern's prompt engineering capabilities to Ruby applications — giving you fine-grained control over context construction, macro expansion, character cards, and more.

## ✨ Features

- **Pipeline Architecture** — Rack-inspired middleware pattern for fully customizable prompt construction
- **Ruby DSL** — Elegant domain-specific language for configuring prompts
- **Character Card V2/V3 Support** — Parse and use [Character Card V2](https://github.com/malfoyslastname/character-card-spec-v2) and [V3](https://github.com/kwaroran/character-card-spec-v3) formats
- **PNG Read/Write** — Extract cards from PNG files and embed character data into images
- **Macro System** — Expand `{{char}}`, `{{user}}`, `{{date}}`, `{{roll:d20}}`, `{{var::name}}`, and 50+ other placeholders
- **Preset System** — Configure main prompts, post-history instructions, and override behaviors
- **User/Persona** — Define user personas for richer roleplay context
- **Prompt Blocks** — The built prompt is an ordered list of structured blocks (easy to inspect/debug)
- **Example Messages** — `mes_example` parsed into real `user` / `assistant` message blocks
- **World Info / Lorebook** — Full feature set:
  - Character Book + Global Lore merge with insertion strategies
  - Optional Filter logic (AND ANY/ALL, NOT ANY/ALL)
  - Recursive scanning with safety limits
  - Token budget with priority-based selection
  - All insertion positions (@depth, outlets, AN, etc.)
  - Generation Type Triggers (normal, continue, impersonate, swipe, regenerate, quiet)
  - Timed effects (sticky, cooldown, delay)
  - Min activations scanning
  - Group scoring and weights
- **Prompt Manager** — Ordered prompt entries with in-chat injection and conditional activation
- **Context Trimming** — Automatic eviction (examples → lore → history) when over budget
- **Token Estimation** — Accurate tiktoken_ruby integration (required dependency)
- **Output Dialects** — OpenAI, Anthropic, Cohere, Google, AI21, Mistral, xAI, and text completion formats
- **Injection Registry** — Programmatic prompt injections (STscript `/inject` parity)
- **Build-Time Hooks** — `before_build` and `after_build` hooks for advanced customization
- **Variable Macros** — `{{setvar::}}`, `{{getvar::}}` with pluggable storage backends
- **CLI Tools** — Validate cards, build prompts, extract/convert cards, and test lorebook triggering
- **Extensible Middleware** — Replace, insert, or remove pipeline stages for custom behavior

## 🗺️ Roadmap

TavernKit is developed in phases. See [ROADMAP.md](ROADMAP.md) for detailed plans.

| Phase | Focus | Status |
|-------|-------|--------|
| **Phase 0** | Foundation (Card V2, Macros, Preset, Builder) | ✅ Complete |
| **Phase 1** | World Info / Lorebook, Examples, CLI | ✅ Complete |
| **Phase 1.5** | Prompt Manager, Context Trimming | ✅ Complete |
| **Phase 1.6** | Character Card V2/V3 Schema Alignment | ✅ Complete |
| **Phase 2** | Top-Level API & Developer Experience | ✅ Complete |
| **Phase 3** | Advanced Prompt Control (Hooks, Conditional Entries, Injections) | ✅ Complete |
| **Phase 4** | Extended Macros, Memory System, RAG | 🚧 Partial |
| **Phase 5** | Ecosystem & Integrations | 🚧 Partial |

## 📦 Installation

Add this line to your application's Gemfile:

```ruby
gem "tavern_kit"
```

And then execute:

```bash
bundle install
```

Or install it yourself:

```bash
gem install tavern_kit
```

## 🚀 Quick Start

### DSL Style (Recommended)

```ruby
require "tavern_kit"

# Load a character card
card = TavernKit.load_character("path/to/card.png")  # or .json

# Build prompt with the elegant DSL
plan = TavernKit.build do
  character card
  user "Alice"
  message "Hello!"
end

# Get messages in OpenAI format
messages = plan.to_messages
# => [{role: "system", content: "..."}, {role: "user", content: "..."}]

# Send to your LLM client
response = openai_client.chat(parameters: { model: "gpt-4", messages: messages })
```

### Direct to Messages (One-liner)

```ruby
# Build and convert to messages in one call
messages = TavernKit.to_messages(dialect: :openai) do
  character TavernKit.load_character("card.png")
  user "Alice"
  message "Hello!"
end

# For Anthropic
result = TavernKit.to_messages(dialect: :anthropic) do
  character TavernKit.load_character("card.png")
  user "Alice"
  message "Hello!"
end
# => {messages: [...], system: [...]}
```

### Different Output Formats (Dialects)

```ruby
card = TavernKit.load_character("card.png")

# OpenAI format (default)
messages = TavernKit.to_messages(dialect: :openai) do
  character card
  user "Alice"
  message "Hello!"
end

# Anthropic format (for Claude API)
result = TavernKit.to_messages(dialect: :anthropic) do
  character card
  user "Alice"
  message "Hello!"
end
# => {messages: [{role: "user", content: [{type: "text", text: "..."}]}], system: [...]}

# Google/Gemini format
result = TavernKit.to_messages(dialect: :google) do
  character card
  user "Alice"
  message "Hello!"
end
# => {contents: [...], system_instruction: {...}}

# Text completion format (for legacy models)
text = TavernKit.to_messages(dialect: :text) do
  character card
  user "Alice"
  message "Hello!"
end
# => "System: ...\nuser: ...\nassistant:"
```

### With Full Options

```ruby
card = TavernKit.load_character("card.png")
lore = TavernKit::Lore::Book.load_file("world.json", source: :global)

plan = TavernKit.build do
  character card
  user name: "Alice", persona: "A curious traveler"
  preset main_prompt: "...", prefer_char_prompt: true
  history previous_messages
  lore_books [lore]
  group members: ["Alice", "Bob"], current_character: "Alice"
  generation_type :normal
  message "Hello!"
end

messages = plan.to_messages(dialect: :openai)
```

### With Custom Middleware

```ruby
# Create custom middleware for your needs
class LoggingMiddleware < TavernKit::Prompt::Middleware::Base
  def before(context)
    Rails.logger.info "Building prompt for #{context.character&.name}"
    context
  end

  def after(context)
    Rails.logger.info "Built #{context.plan&.blocks&.size || 0} blocks"
    context
  end
end

# Use in your build
plan = TavernKit.build do
  character my_char
  user my_user

  # Add custom middleware
  use LoggingMiddleware

  # Or replace built-in middleware
  replace :trimming, MyCustomTrimmer

  message "Hello!"
end
```

### Keyword Arguments Style

```ruby
# Alternative to DSL blocks - use keyword arguments
plan = TavernKit.build(
  character: TavernKit.load_character("card.png"),
  user: { name: "Alice", persona: "A curious traveler" },
  preset: { main_prompt: "...", prefer_char_prompt: true },
  history: previous_messages,
  lore_books: ["world_info.json"],
  message: "Hello!"
)

messages = plan.to_messages(dialect: :openai)
```

### Convenience Loaders

```ruby
# Load character from any source (JSON, PNG, Hash)
character = TavernKit.load_character("path/to/card.png")

# Load preset (auto-detects SillyTavern format)
preset = TavernKit.load_preset("path/to/preset.json")
preset = TavernKit.load_preset(main_prompt: "Simple preset")

# Access the default pipeline
pipeline = TavernKit.pipeline

# Access the global macro registry
TavernKit.macros.register("mymacro") { |ctx| "custom value" }
```

### Full Configuration Example

```ruby
# Load a character (supports V2/V3 JSON, PNG, or Hash)
card = TavernKit::CharacterCard.load("seraphina.json")

# Define the user
my_user = TavernKit::User.new(name: "Alex", persona: "A curious traveler")

# Create a preset (or use defaults)
my_preset = TavernKit::Preset.new(
  main_prompt: "Write {{char}}'s next reply in a fictional chat between {{charIfNotGroup}} and {{user}}.",
  post_history_instructions: "Stay in character.",
  prefer_char_prompt: true,        # Use character's system_prompt if present
  prefer_char_instructions: true,  # Use character's PHI if present
  context_window_tokens: 8000,
  reserved_response_tokens: 1000
)

# Build the prompt using the DSL
plan = TavernKit.build do
  character card
  user my_user
  preset my_preset
  message "Hello, who are you?"
end

# Get messages in your preferred format
messages = plan.to_messages  # OpenAI format (default)
# => [
#   { role: "system", content: "You are Seraphina. Write Seraphina's next reply..." },
#   { role: "system", content: "Seraphina is a forest guardian..." },
#   { role: "user", content: "Hello, who are you?" },
#   { role: "system", content: "Stay in character as Seraphina." }
# ]

# Or use Anthropic format
result = plan.to_messages(dialect: :anthropic)
# => {messages: [...], system: [...]}

# Or plain text for completion APIs
text = plan.to_messages(dialect: :text)
# => "System: ...\nuser: ...\nassistant:"
```

## 🛠 CLI

```bash
# Validate a Character Card V2 JSON
ruby exe/tavern_kit validate-card --card path/to/card.json

# Extract character card from PNG/APNG
ruby exe/tavern_kit extract-card card.png --out card.json --pretty
ruby exe/tavern_kit extract-card cards/ --out-spec v3 --pretty  # batch processing

# Convert character card between v2/v3 formats
ruby exe/tavern_kit convert-card card.json --out-spec v3 --out card_v3.json
ruby exe/tavern_kit convert-card cards/ --out-spec v2 --pretty  # batch processing

# Build a prompt (default: OpenAI-compatible messages JSON)
ruby exe/tavern_kit prompt --card path/to/card.json --user "Alex" --message "Hi"

# Build a prompt (Anthropic Messages API format)
ruby exe/tavern_kit prompt --card path/to/card.json --user "Alex" --message "Hi" --dialect anthropic

# Build a prompt (plain text for completion APIs)
ruby exe/tavern_kit prompt --card path/to/card.json --user "Alex" --message "Hi" --dialect text

# Build with specific generation type (for trigger filtering)
ruby exe/tavern_kit prompt --card card.json --user "Alex" --message "Hi" --generation-type continue

# Test World Info / lorebook triggers, budgeting, and ordering
ruby exe/tavern_kit lore test --book path/to/lore.json --text "some text to scan"
```

## 📖 Core Concepts

### Character

Characters define a character's personality, description, scenario, and optional prompt overrides:

```ruby
character = TavernKit::CharacterCard.load("character.json")  # or .png

character.name                    # => "Seraphina"
character.data.description        # => "A forest guardian..."
character.data.system_prompt      # => "You are {{char}}. {{original}}"
character.source_version          # => :v2 or :v3
```

The `{{original}}` macro allows character-specific prompts to include the preset's default prompt.

### Presets

Presets define your global prompt configuration:

```ruby
preset = TavernKit::Preset.new(
  main_prompt: "...",
  post_history_instructions: "...",
  prefer_char_prompt: true,       # Let character override main_prompt
  prefer_char_instructions: true, # Let character override PHI
  authors_note: "Remember: Stay in character",
  authors_note_frequency: 1,      # Insert every turn (0=never)
  authors_note_position: :in_chat,
  authors_note_depth: 4,
  context_window_tokens: 8000,
  reserved_response_tokens: 1000,
  examples_behavior: :trim        # or :always_keep, :disabled
)
```

### Macros

Macros are placeholders that get expanded at build time:

| Category | Macros |
|----------|--------|
| Identity | `{{char}}`, `{{user}}`, `{{persona}}`, `{{charIfNotGroup}}`, `{{group}}` |
| Character | `{{description}}`, `{{scenario}}`, `{{personality}}`, `{{charPrompt}}` |
| Context | `{{original}}`, `{{input}}`, `{{maxPrompt}}`, `{{outlet::name}}` |
| Date/Time | `{{date}}`, `{{time}}`, `{{weekday}}`, `{{isodate}}`, `{{datetimeformat ...}}` |
| Random | `{{random::a,b,c}}`, `{{pick::a,b,c}}`, `{{roll:d20}}` |
| Variables | `{{setvar::name::value}}`, `{{getvar::name}}`, `{{var::name}}` |
| Utilities | `{{newline}}`, `{{trim}}`, `{{noop}}`, `{{reverse:...}}` |

### Global Lore + Insertion Strategies

Merge global lorebooks with character's embedded lore:

```ruby
card = TavernKit.load_character("card.png")
lore1 = TavernKit::Lore::Book.load_file("world_lore.json", source: :global)
lore2 = TavernKit::Lore::Book.load_file("extra_lore.json", source: :global)

plan = TavernKit.build do
  character card
  user "Alice"
  preset character_lore_insertion_strategy: :global_lore_first
  lore_books [lore1, lore2]
  message "Hello"
end

messages = plan.to_messages
```

### Prompt Manager (Prompt Entries)

Configure the order and behavior of prompt sections:

```ruby
preset = TavernKit::Preset.new(
  prompt_entries: [
    { id: "main_prompt", pinned: true },
    { id: "persona_description", pinned: true },
    { id: "character_description", pinned: true },
    { id: "chat_history", pinned: true },
    # Custom in-chat prompt (injected at depth 0)
    { id: "reminder", role: "system", position: "in_chat", depth: 0, order: 10, content: "Remember to stay in character!" },
    # Conditional entry (only when "dragon" mentioned)
    { id: "dragon_lore", role: "system", position: "in_chat", depth: 2, content: "Dragons breathe fire...", conditions: { chat: { any: ["dragon"] } } },
    { id: "post_history_instructions", pinned: true },
  ]
)
```

### Context Trimming

Automatically trim content when exceeding token budget:

```ruby
card = TavernKit.load_character("card.png")

plan = TavernKit.build do
  character card
  user "Alice"
  preset context_window_tokens: 8000,
         reserved_response_tokens: 1000,
         examples_behavior: :trim  # or :always_keep, :disabled
  message "Hello"
end

# Check what was trimmed
puts plan.trim_report
# => { removed_example_blocks: [0, 1], removed_lore_uids: ["entry_5"], removed_history_messages: 3 }
```

### Generation Type Triggers

Control when World Info entries and Prompt Manager entries activate based on the generation type:

```ruby
card = TavernKit.load_character("card.png")

# Specify generation type in the DSL
plan = TavernKit.build do
  character card
  user "Alice"
  generation_type :continue  # :normal, :continue, :impersonate, :swipe, :regenerate, :quiet
  message "Hello"
end

# Entries with empty triggers [] activate for ALL types (default)
# Entries with specific triggers only activate when generation_type matches
```

### Variable Macros

Use variables that persist across builds:

```ruby
# Create a variable store
vars = TavernKit::ChatVariables.new
card = TavernKit.load_character("card.png")

# Variables set via {{setvar::name::value}} persist in the store
plan = TavernKit.build do
  character card
  user "Alice"
  macro_vars local_store: vars
  message "Set my name: {{setvar::myname::Bob}}"
end

# Access via {{getvar::name}} or {{var::name}}
plan = TavernKit.build do
  character card
  user "Alice"
  macro_vars local_store: vars
  message "My name is {{getvar::myname}}"  # => "My name is Bob"
end
```

### Prompt Plan

The `Prompt::Plan` holds the final message array:

```ruby
plan.messages                              # => Array of TavernKit::Prompt::Message
plan.enabled_blocks                        # => Only enabled blocks
plan.to_messages                           # => OpenAI format (default)
plan.to_messages(dialect: :openai)         # => [{role:, content:}]
plan.to_messages(dialect: :anthropic)      # => {messages: [...], system: [...]}
plan.to_messages(dialect: :text)           # => "System: ...\nassistant:"
plan.debug_dump                            # => Human-readable string for debugging
plan.trim_report                           # => What was trimmed (if context exceeded)
plan.warnings                              # => Non-fatal warnings (unknown IDs, etc.)
plan.greeting                              # => Selected greeting text (macros expanded)
```

## 🧪 Development

### Prerequisites

Before getting started, ensure you have the following installed:

- **Ruby 3.4.0+** — The minimum Ruby version required
- **Bundler** — For managing Ruby dependencies (`gem install bundler`)

For the **playground** app (optional):

- **Bun** — JavaScript runtime for the frontend ([installation guide](https://bun.sh/docs/installation))
- **SQLite** — The playground uses SQLite as its database. You may need to install system dependencies:

  ```bash
  # macOS (usually pre-installed, or via Homebrew)
  brew install sqlite

  # Ubuntu/Debian
  sudo apt-get install libsqlite3-dev

  # Fedora
  sudo dnf install sqlite-devel

  # Arch Linux
  sudo pacman -S sqlite
  ```

### Getting Started

After checking out the repo, run:

```bash
bin/setup          # Install dependencies
rake test          # Run tests
bin/console        # Interactive prompt
```

### Running Tests

```bash
bundle exec rake test
```

### Code Style

```bash
bundle exec rubocop -A
```

### Type Checking (RBS)

```bash
bundle exec rbs validate
bundle exec steep check  # If using Steep
```

## 🤝 Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jasl/tavern_kit.

See [ARCHITECTURE.md](ARCHITECTURE.md) for design decisions and module responsibilities.

## 🙏 Acknowledgments

- [SillyTavern](https://github.com/SillyTavern/SillyTavern) — The original inspiration
- [Character Card V2 Spec](https://github.com/malfoyslastname/character-card-spec-v2) — V2 character format
- [Character Card V3 Spec](https://github.com/kwaroran/character-card-spec-v3) — V3 character format

## 📄 License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
