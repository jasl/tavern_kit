# Character Card V3 (CCv3 / `chara_card_v3`) — Interop Notes

## 0. Scope

This document focuses on the CCv3 shape most commonly encountered in the SillyTavern ecosystem:
JSON exports tagged as `spec: "chara_card_v3"` with `spec_version: "3.0"`.

We describe:
- minimal fields needed for prompt building,
- forward-compatible parsing rules,
- common additions (assets, group-only greetings, etc.)
- file formats and embedding methods (JSON, PNG, CharX)

## 1. Identification (observed)

A CCv3 card in the wild typically contains:
- `spec`: MUST be `"chara_card_v3"`
- `spec_version`: typically `"3.0"`
- `data`: object containing card content

Many exports ALSO include legacy fields at the root (name/description/etc.) for compatibility.

## 2. Canonical data location

- `data` SHOULD be treated as canonical.
- Root-level duplicated fields SHOULD be treated as legacy mirrors.

## 3. Minimal fields for prompt-building

Your prompt builder SHOULD support at least these `data.*` fields:

- `data.name: string`
- `data.description: string`
- `data.personality: string`
- `data.scenario: string`
- `data.first_mes: string`
- `data.mes_example: string`

Prompt-control fields:
- `data.creator_notes: string` (notes for users)
- `data.system_prompt: string` (system/main prompt override)
- `data.post_history_instructions: string` (post-history instructions)
- `data.alternate_greetings: string[]`

Group-chat related:
- `data.group_only_greetings: string[]` (greetings used only in group contexts)

Optional organization metadata:
- `data.tags: string[]`
- `data.creator: string`
- `data.character_version: string`

Optional knowledge attachment:
- `data.character_book: object` (lorebook; see CCv2 notes re: preserving unknown)

## 4. Notable additions often associated with CCv3

CCv3 is often described as extending CCv2 with new features (proposal spec).
In tools that target CCv3, you may see additional substructures such as:
- `data.assets: array` (e.g., icon/background/live2d/etc.)
- `data.nickname: string` (character nickname)
- `data.creator_notes_multilingual: object` (localized creator notes per language code)
- `data.source: string[]` (source URLs/references)
- `data.creation_date: integer` (Unix timestamp)
- `data.modification_date: integer` (Unix timestamp)

Because the exact sub-schema may vary across apps, treat unknown sub-objects as opaque by default.

## 5. Extensions and app-specific data

Implementations MUST preserve unknown fields:
- root unknown fields
- `data` unknown fields
- `data.extensions` unknown fields (if present)

Rule of thumb:
- If you need to store app-specific state, prefer `data.extensions` (or a designated extension slot),
  so it won't collide with future spec fields.

## 6. File Formats and Embedding Methods

### 6.1 JSON Files

Direct JSON files (`.json`) contain the card data as a JSON object with the structure
described above. This is the simplest format.

### 6.2 PNG/APNG Embedding

Character cards can be embedded in PNG or APNG images as tEXt chunks:

- **CCv3 chunk**: keyword `ccv3`, value is base64-encoded UTF-8 JSON
- **Legacy chunk**: keyword `chara`, value is base64-encoded UTF-8 JSON (CCv2 format)

When both chunks exist, `ccv3` takes precedence.

Additional asset chunks may be present:
- **Asset chunks**: keyword `chara-ext-asset_:N` (where N is an index), value is base64-encoded binary

### 6.3 CharX Format (ZIP Archive)

CharX (`.charx`) is a ZIP archive format introduced by RisuAI for CCv3 cards with
embedded assets. It provides a portable way to bundle the character card with
all associated media files.

#### CharX Structure

```
character.charx (ZIP archive)
├── card.json          # Required: CCv3 character card data
├── module.risum       # Optional: RisuAI module data (ignored by most parsers)
├── x_meta/            # Optional: RisuAI asset metadata (e.g., {"type":"WEBP"})
│   ├── 1.json
│   └── ...
└── assets/            # Optional: embedded asset files
    ├── icon/
    │   └── main.png
    ├── emotion/
    │   ├── happy.png
    │   └── sad.png
    └── background/
        └── default.jpg
```

> **Note:** RisuAI exports may include an `x_meta/` directory containing JSON files
> with metadata for each asset. This metadata may include the actual file type when
> it differs from the declared extension. Parsers SHOULD allow but MAY ignore this
> directory.

#### card.json

The `card.json` file MUST contain a valid CCv3 character card. This is the only
required file in a CharX archive.

#### Asset URI Schemes

Assets in `data.assets` array can reference embedded files using these URI schemes:

| Scheme | Description | Example |
|--------|-------------|---------|
| `embeded://path` | File embedded in ZIP (note: "embeded" not "embedded") | `embeded://assets/icon/main.png` |
| `ccdefault:` | Default/placeholder icon | `ccdefault:` |
| `__asset:N` | Legacy PNG chunk reference (from PNG embedding) | `__asset:0` |
| `data:` | Inline data URI | `data:image/png;base64,iVBOR...` |

#### Asset Object Structure

Each asset in `data.assets` array follows this structure:

```json
{
  "type": "icon",           // Asset kind: icon, emotion, background, user_icon, other
  "name": "main",           // Unique identifier within the character
  "uri": "embeded://path",  // URI to the asset content
  "ext": "png"              // File extension without dot
}
```

> **Note:** Some RisuAI exports declare file extensions (e.g., `"ext": "png"`) that
> do not match the actual content type (e.g., WEBP). Parsers SHOULD detect the
> actual content type from magic bytes and use the detected extension when there
> is a mismatch, rather than rejecting the asset.

#### JPEG-Wrapped CharX (RisuAI Format)

Some CharX files are distributed as JPEG images with the ZIP archive appended
after the JPEG data. This allows the file to be viewed as an image while still
containing the full CharX data.

Detection: File starts with JPEG signature (`FF D8 FF`) but contains ZIP
signature (`PK\x03\x04`) later in the file. Extract from the ZIP signature
position to the end of the file.

#### CharX Import Algorithm

```ruby
# 1. Read file content
content = file.read

# 2. Check for JPEG wrapper
if content.start_with?("\xFF\xD8\xFF") && content.include?("PK\x03\x04")
  zip_start = content.index("PK\x03\x04")
  content = content[zip_start..]
end

# 3. Open as ZIP
Zip::File.open_buffer(content) do |zip|
  # 4. Extract card.json
  card_entry = zip.find_entry("card.json")
  raise "Invalid CharX: missing card.json" unless card_entry
  
  card_hash = JSON.parse(card_entry.get_input_stream.read)
  
  # 5. Process assets
  assets = card_hash.dig("data", "assets") || []
  assets.each do |asset|
    case asset["uri"]
    when /^embeded:\/\/(.+)$/
      path = $1
      entry = zip.find_entry(path)
      content = entry&.get_input_stream&.read
      # Store asset with content
    when "ccdefault:"
      # Skip default placeholder
    when /^data:/
      # Decode inline data URI
    end
  end
end
```

## 7. Export guidance (interop-first)

When exporting CCv3:
- write canonical fields under `data`
- for compatibility, also mirror core legacy fields at the root:
  `name/description/personality/scenario/first_mes/mes_example/tags/...`

This improves importability by older tools that ignore `data`.

When exporting to CharX:
- Create a ZIP archive with `card.json` at the root
- Store assets in appropriate subdirectories under `assets/`
- Use `embeded://` URIs to reference embedded files
- Consider including a fallback icon at `assets/icon/main.png`

## 8. Conformance checklist (summary)

An implementation is "CCv3-interoperable" for this repo if it:
- recognizes `spec="chara_card_v3"` and `spec_version`
- parses minimal prompt-building fields from `data`
- preserves unknown fields (forward compatibility)
- mirrors fields appropriately on export (optional but recommended)

For CharX support:
- correctly extracts `card.json` from ZIP archives
- resolves `embeded://` URIs to embedded files
- handles JPEG-wrapped CharX files (optional but recommended)
- preserves unknown asset types and URIs
