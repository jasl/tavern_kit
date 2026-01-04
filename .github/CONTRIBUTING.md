# Contributing to TavernKit

Thank you for your interest in contributing to TavernKit! This document provides guidelines and instructions for contributing.

## Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/tavern_kit.git
   cd tavern_kit
   ```

2. **Install dependencies**
   ```bash
   bin/setup
   ```

3. **Run tests**
   ```bash
   bundle exec rake test
   ```

4. **Interactive console**
   ```bash
   bin/console
   ```

## Code Style

- Follow standard Ruby style conventions
- Use `frozen_string_literal: true` pragma
- Add YARD documentation for public methods
- Keep methods small and focused
- **No trailing blank lines** — Run `ruby bin/lint-eof --fix` before committing

## Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/my-new-feature
   ```

2. **Make your changes**
   - Write tests for new functionality
   - Update documentation as needed
   - Follow existing code patterns

3. **Run the test suite and lints**
   ```bash
   bundle exec rake test
   ruby bin/lint-eof
   ```

4. **Submit a pull request**
   - Describe what changes you made
   - Reference any related issues

## Adding New Features

### New Macro

1. Add handling in `Macro::V1::Engine#expand`
2. Pass the value in `Prompt::Builder#expand_macros`
3. Add test in `test/macro/test_expander.rb`
4. Document in `README.md` macro table

### New Character Card Field

1. Add field to `CharacterCard::V2::Data` Struct
2. Parse in `CharacterCard::V2.from_hash`
3. Use in `Prompt::Builder` as needed
4. Add test in `test/character_card/test_v2.rb`

### New Prompt Block

1. Add `build_*` method to `Prompt::Builder`
2. Call in correct position within `#build`
3. Consider `Preset` options for enable/disable
4. Add test in `test/prompt/test_builder.rb`

## Testing

- Use Minitest (not RSpec)
- Place fixtures in `test/fixtures/`
- Test both happy path and error cases
- Test files are organized by module:
  - `test/character_card/test_v2.rb` — CharacterCard tests
  - `test/prompt/test_builder.rb` — Prompt::Builder tests
  - `test/test_tavern_kit.rb` — General/version tests

## Documentation

- Update `README.md` for user-facing changes
- Update `ARCHITECTURE.md` for internal design changes
- Add YARD docs for new public APIs
- Update `.cursor/rules` for AI assistant context

## Reporting Issues

When reporting bugs, please include:
- Ruby version (`ruby -v`)
- TavernKit version
- Minimal reproduction code
- Expected vs actual behavior

## Questions?

Feel free to open an issue for questions or discussions about the codebase.
