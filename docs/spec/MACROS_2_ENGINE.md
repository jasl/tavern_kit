# Macros 2.0 Engine

TavernKit provides two macro expanders:

- **`TavernKit::Macro::V2::Engine`** (default) — parser-based expansion targeting SillyTavern's experimental
  **MacroEngine / "Macros 2.0"** behavior.
- **`TavernKit::Macro::V1::Engine`** (legacy, opt-in) — regex-based, multi-pass expansion that matches
  SillyTavern's *legacy* macro evaluation.

This document describes `TavernKit::Macro::V2::Engine`.

## Why a second engine?

Legacy expansion works well for "flat" macros and many common ST patterns, but it is fundamentally
regex-driven and relies on a pass order (pre-env → env → post-env) to make "nested" patterns work.

The Macros 2.0 engine instead parses the input and supports **true nesting inside macro arguments**,
with a stable, depth-first evaluation order.

## Enabling the Macros 2.0 engine

In the TavernKit DSL:

```ruby
plan = TavernKit.build do
  # This is the default.
  macro_engine :v2
end
```

Or set the expander explicitly:

```ruby
plan = TavernKit.build do
  expander TavernKit::Macro::V2::Engine.new
end
```

To force the legacy expander:

```ruby
plan = TavernKit.build do
  macro_engine :legacy
end
```

Or directly:

```ruby
engine = TavernKit::Macro::V2::Engine.new
engine.expand("Hello {{user}}", { user: "Alice" })
```

## Supported syntax

### Basic macros

```text
{{user}}
{{char}}
{{random::a,b,c}}
```

Macro names are case-insensitive.

### Nested macros

Macros may appear **inside** other macro payloads:

```text
{{reverse::{{user}}}}
{{setvar::greeting::Hello {{user}}}}
```

Nested macros are evaluated first.

### Unknown macros

Unknown macros are preserved **as macros**, but any nested known macros inside them are still
expanded:

```text
{{unknown::{{user}}}}  →  {{unknown::Alice}}
```

You can change the policy via `unknown:`:

```ruby
TavernKit::Macro::V2::Engine.new(unknown: :empty)
```

### Braces near macros

SillyTavern's MacroEngine tolerates stray braces near macros.
TavernKit::Macro::V2::Engine mirrors this behavior:

```text
{{{char}}}    →  {Character}
{{char}}}     →  Character}
{{{{char}}}}  →  {{Character}}
```

### Unterminated macros

Unterminated macro openers are treated as plain text, but later valid macros still expand:

```text
Test {{ hehe {{user}}  →  Test {{ hehe User
```

### Comments

SillyTavern-style comments are removed:

```text
{{// this disappears}}
```

### `{{trim}}`

`{{trim}}` is treated as a post-processing directive: it is removed along with any surrounding
newlines.

### Escaping

Use `\{{` / `\}}` to emit literal braces without starting/ending a macro. After expansion, `\{` and
`\}` are unescaped to `{` and `}`.

## Deterministic `{{pick}}`

`TavernKit::Macro::V2::Engine` builds `Macro::Invocation` offsets based on the **original input**
string. This improves determinism vs. legacy multi-pass expansion for macros such as `{{pick}}`.

## Custom macros

Macro implementations are still provided via:

- **Env macros** (`vars` hash passed to `expand`), and
- **Builtins** (`builtins_registry:`), which defaults to
  `TavernKit::Macro::Packs::SillyTavern.utilities_registry`.

You can add app-specific macros by registering them into `TavernKit.macros` (env macros) or by
providing a custom `builtins_registry:`.

In TavernKit prompt building, `TavernKit.macros` is used to populate the env automatically. When
calling `Engine#expand` directly, pass custom macros via the `vars` hash (or a custom
`builtins_registry:`).

## Macro result normalization

`TavernKit::Macro::V2::Engine` normalizes macro return values similarly to ST's MacroEngine:

- `nil` → `""`
- `Hash` / `Array` → JSON
- `Date` / `Time` → ISO 8601 UTC
