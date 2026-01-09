# frozen_string_literal: true

require "test_helper"

class DuplicatableTest < ActiveSupport::TestCase
  # Use Preset as the test subject since it includes Duplicatable
  # and has straightforward copy logic

  setup do
    @preset = Preset.create!(
      name: "Original Preset",
      description: "Original description",
      generation_settings: { temperature: 1.0, max_response_tokens: 512 },
      preset_settings: { main_prompt: "Test prompt" }
    )
  end

  # --- Preset duplication ---

  test "create_copy! creates a new saved preset" do
    copy = @preset.create_copy!

    assert copy.persisted?
    assert_not_equal @preset.id, copy.id
    assert_equal "Original Preset (Copy)", copy.name
    assert_equal @preset.description, copy.description
  end

  test "create_copy! copies generation_settings" do
    copy = @preset.create_copy!

    assert_equal @preset.generation_settings_as_hash, copy.generation_settings_as_hash
  end

  test "create_copy! copies preset_settings" do
    copy = @preset.create_copy!

    assert_equal @preset.preset_settings_as_hash, copy.preset_settings_as_hash
  end

  test "create_copy! does not copy locked_at" do
    @preset.lock!
    copy = @preset.create_copy!

    assert_nil copy.locked_at
    assert_not copy.locked?
  end

  test "create_copy! creates a private (draft) copy" do
    # Copies start as private/draft, even if the original is public
    @preset.publish!
    copy = @preset.create_copy!

    assert copy.draft?
    assert_equal "private", copy.visibility
  end

  test "create_copy! allows overriding attributes" do
    copy = @preset.create_copy!(name: "Custom Name", description: "Custom description")

    assert_equal "Custom Name", copy.name
    assert_equal "Custom description", copy.description
  end

  test "create_copy returns unpersisted record on validation failure" do
    # Create a preset that would cause name conflict when copied
    Preset.create!(name: "Original Preset (Copy)")

    copy = @preset.create_copy

    assert_not copy.persisted?
    assert copy.errors[:name].any?
  end

  test "create_copy! raises on validation failure" do
    # Create a preset that would cause name conflict when copied
    Preset.create!(name: "Original Preset (Copy)")

    assert_raises(ActiveRecord::RecordInvalid) do
      @preset.create_copy!
    end
  end
end

class LorebookDuplicatableTest < ActiveSupport::TestCase
  setup do
    @lorebook = Lorebook.create!(
      name: "Test Lorebook",
      description: "Test description",
      scan_depth: 5,
      token_budget: 1000,
      recursive_scanning: true,
      settings: { custom: "setting" }
    )

    # Add entries
    @lorebook.entries.create!(
      uid: "entry1",
      keys: %w[dragon fire],
      content: "Dragons breathe fire",
      enabled: true,
      insertion_order: 100
    )
    @lorebook.entries.create!(
      uid: "entry2",
      keys: %w[elf forest],
      content: "Elves live in forests",
      enabled: false,
      insertion_order: 200
    )
  end

  test "create_copy! creates a new saved lorebook" do
    copy = @lorebook.create_copy!

    assert copy.persisted?
    assert_not_equal @lorebook.id, copy.id
    assert_equal "Test Lorebook (Copy)", copy.name
  end

  test "create_copy! copies basic attributes" do
    copy = @lorebook.create_copy!

    assert_equal @lorebook.description, copy.description
    assert_equal @lorebook.scan_depth, copy.scan_depth
    assert_equal @lorebook.token_budget, copy.token_budget
    assert_equal @lorebook.recursive_scanning, copy.recursive_scanning
    assert_equal @lorebook.settings, copy.settings
  end

  test "create_copy! copies all entries" do
    copy = @lorebook.create_copy!

    assert_equal 2, copy.entries.count

    entry1_copy = copy.entries.find_by(uid: "entry1")
    assert_not_nil entry1_copy
    assert_equal %w[dragon fire], entry1_copy.keys
    assert_equal "Dragons breathe fire", entry1_copy.content
    assert entry1_copy.enabled

    entry2_copy = copy.entries.find_by(uid: "entry2")
    assert_not_nil entry2_copy
    assert_equal %w[elf forest], entry2_copy.keys
    assert_not entry2_copy.enabled
  end

  test "create_copy! creates independent entries" do
    copy = @lorebook.create_copy!

    # Modify original entries
    @lorebook.entries.first.update!(content: "Modified content")

    # Copy entries should be unchanged
    copy_entry = copy.entries.find_by(uid: "entry1")
    assert_equal "Dragons breathe fire", copy_entry.content
  end

  test "create_copy! preserves entry attributes" do
    entry = @lorebook.entries.create!(
      uid: "detailed",
      keys: %w[test],
      secondary_keys: %w[secondary],
      content: "Content",
      comment: "A comment",
      enabled: true,
      constant: true,
      selective: true,
      selective_logic: "and_all",
      insertion_order: 500,
      position: "top_of_an",
      depth: 2,
      role: "user",
      probability: 75,
      group: "TestGroup",
      group_weight: 3
    )

    copy = @lorebook.create_copy!
    copy_entry = copy.entries.find_by(uid: "detailed")

    assert_equal entry.keys, copy_entry.keys
    assert_equal entry.secondary_keys, copy_entry.secondary_keys
    assert_equal entry.content, copy_entry.content
    assert_equal entry.comment, copy_entry.comment
    assert_equal entry.enabled, copy_entry.enabled
    assert_equal entry.constant, copy_entry.constant
    assert_equal entry.selective, copy_entry.selective
    assert_equal entry.selective_logic, copy_entry.selective_logic
    assert_equal entry.insertion_order, copy_entry.insertion_order
    assert_equal entry.position, copy_entry.position
    assert_equal entry.depth, copy_entry.depth
    assert_equal entry.role, copy_entry.role
    assert_equal entry.probability, copy_entry.probability
    assert_equal entry.group, copy_entry.group
    assert_equal entry.group_weight, copy_entry.group_weight
  end
end

class CharacterDuplicatableTest < ActiveSupport::TestCase
  setup do
    @character = Character.create!(
      name: "Test Character",
      spec_version: 2,
      tags: %w[fantasy adventure],
      personality: "Brave and kind",
      supported_languages: %w[en ja],
      status: "ready",
      data: {
        name: "Test Character",
        nickname: "Testy", # nickname in data is extracted to column
        description: "A brave adventurer",
        personality: "Brave and kind",
        scenario: "In a fantasy world",
        first_mes: "Hello traveler!",
        mes_example: "<START>",
        creator: "TestCreator",
        character_version: "1.0",
        tags: %w[fantasy adventure],
      },
      authors_note_settings: {
        use_character_authors_note: true,
        authors_note: "Remember: be heroic",
        authors_note_depth: 4,
      }
    )
  end

  test "create_copy! creates a new saved character" do
    copy = @character.create_copy!

    assert copy.persisted?
    assert_not_equal @character.id, copy.id
    assert_equal "Test Character (Copy)", copy.name
  end

  test "create_copy! copies basic attributes" do
    copy = @character.create_copy!

    assert_equal @character.nickname, copy.nickname
    assert_equal @character.spec_version, copy.spec_version
    assert_equal @character.personality, copy.personality
    assert_equal "ready", copy.status
  end

  test "create_copy! copies tags as independent array" do
    copy = @character.create_copy!

    assert_equal @character.tags, copy.tags

    # Modify original
    @character.tags << "modified"
    @character.save!

    # Copy should be unchanged
    assert_not_includes copy.tags, "modified"
  end

  test "create_copy! copies data with updated name" do
    copy = @character.create_copy!

    assert_equal "Test Character (Copy)", copy.data.name
    assert_equal @character.data.description, copy.data.description
    assert_equal @character.data.personality, copy.data.personality
    assert_equal @character.data.scenario, copy.data.scenario
    assert_equal @character.data.first_mes, copy.data.first_mes
    assert_equal @character.data.creator, copy.data.creator
  end

  test "create_copy! copies authors_note_settings" do
    copy = @character.create_copy!

    assert copy.effective_authors_note_settings.use_character_authors_note
    assert_equal "Remember: be heroic", copy.effective_authors_note_settings.authors_note
    assert_equal 4, copy.effective_authors_note_settings.authors_note_depth
  end

  test "create_copy! creates independent data copy" do
    copy = @character.create_copy!

    # Modify original data (use string key to avoid duplicate key warning)
    original_data = @character.data.to_h.deep_stringify_keys
    original_data["description"] = "Modified description"
    @character.update!(data: original_data)

    # Copy data should be unchanged
    assert_equal "A brave adventurer", copy.data.description
  end

  test "create_copy! allows setting user override" do
    user = User.create!(
      name: "Test User",
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    copy = @character.create_copy!(user: user)

    assert_equal user, copy.user
  end

  test "create_copy! does not copy file_sha256" do
    @character.update!(file_sha256: "abc123")
    copy = @character.create_copy!

    assert_nil copy.file_sha256
  end

  test "create_copy! copies character_assets with blob reuse" do
    # Create a blob for testing
    content = "test image content"
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: "test.png",
      content_type: "image/png"
    )

    # Create character assets
    @character.character_assets.create!(
      blob: blob,
      name: "happy",
      kind: "emotion",
      ext: "png",
      content_sha256: Digest::SHA256.hexdigest(content)
    )
    @character.character_assets.create!(
      blob: blob,
      name: "sad",
      kind: "emotion",
      ext: "png",
      content_sha256: Digest::SHA256.hexdigest(content)
    )

    # Copy the character
    copy = @character.create_copy!

    # Verify assets were copied
    assert_equal 2, copy.character_assets.count
    assert_equal %w[happy sad].sort, copy.character_assets.pluck(:name).sort

    # Verify blob is reused (same blob_id)
    original_blob_ids = @character.character_assets.pluck(:blob_id)
    copy_blob_ids = copy.character_assets.pluck(:blob_id)
    assert_equal original_blob_ids.sort, copy_blob_ids.sort

    # Verify the blob itself was not duplicated
    assert_equal 1, ActiveStorage::Blob.where(id: original_blob_ids).count
  end

  test "create_copy! copies character_assets with correct attributes" do
    content = "test content"
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: "icon.webp",
      content_type: "image/webp"
    )
    content_sha256 = Digest::SHA256.hexdigest(content)

    @character.character_assets.create!(
      blob: blob,
      name: "main",
      kind: "icon",
      ext: "webp",
      content_sha256: content_sha256
    )

    copy = @character.create_copy!

    copy_asset = copy.character_assets.find_by(name: "main")
    assert_not_nil copy_asset
    assert_equal "icon", copy_asset.kind
    assert_equal "webp", copy_asset.ext
    assert_equal content_sha256, copy_asset.content_sha256
    assert_equal blob.id, copy_asset.blob_id
  end
end
