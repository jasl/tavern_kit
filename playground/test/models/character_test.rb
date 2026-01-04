# frozen_string_literal: true

require "test_helper"

class CharacterTest < ActiveSupport::TestCase
  fixtures :characters

  # === Validations ===

  test "valid with all required attributes" do
    character = Character.new(
      name: "Test Character",
      data: { "name" => "Test Character", "description" => "Test" },
      spec_version: 2,
      status: "pending"
    )
    assert character.valid?
  end

  test "invalid without name" do
    character = Character.new(
      data: { "description" => "Test" },
      spec_version: 2
    )
    assert_not character.valid?
    assert_includes character.errors[:name], "can't be blank"
  end

  test "invalid without spec_version when not pending" do
    character = Character.new(
      name: "Test",
      data: { "name" => "Test" },
      status: "ready"
    )
    assert_not character.valid?
    assert_includes character.errors[:spec_version], "can't be blank"
  end

  test "valid without spec_version when pending" do
    character = Character.new(
      name: "Test",
      status: "pending"
    )
    assert character.valid?
  end

  test "valid without data when pending" do
    character = Character.new(
      name: "Test Placeholder",
      status: "pending"
    )
    assert character.valid?
  end

  test "invalid without data when not pending" do
    character = Character.new(
      name: "Test",
      spec_version: 2,
      status: "ready"
    )
    assert_not character.valid?
    assert_includes character.errors[:data], "can't be blank"
  end

  test "invalid with unsupported spec_version" do
    character = Character.new(
      name: "Test",
      data: { "name" => "Test" },
      spec_version: 4
    )
    assert_not character.valid?
    assert_includes character.errors[:spec_version], "is not included in the list"
  end

  test "invalid with unsupported status" do
    character = Character.new(
      name: "Test",
      data: { "name" => "Test" },
      spec_version: 2,
      status: "unknown"
    )
    assert_not character.valid?
    assert_includes character.errors[:status], "is not included in the list"
  end

  # === Status Methods ===

  test "mark_ready! changes status to ready" do
    character = characters(:pending_character)
    character.mark_ready!
    assert_equal "ready", character.reload.status
  end

  test "mark_failed! changes status and stores error" do
    character = characters(:pending_character)
    character.mark_failed!("Test error")
    character.reload
    assert_equal "failed", character.status
    assert_equal "Test error", character.data["_import_error"]
  end

  test "mark_deleting! changes status to deleting" do
    character = characters(:ready_v2)
    character.mark_deleting!
    assert_equal "deleting", character.reload.status
  end

  test "pending? returns true for pending status" do
    assert characters(:pending_character).pending?
    assert_not characters(:ready_v2).pending?
  end

  test "ready? returns true for ready status" do
    assert characters(:ready_v2).ready?
    assert_not characters(:pending_character).ready?
  end

  # === Version Methods ===

  test "v3? returns true for spec_version 3" do
    assert characters(:ready_v3).v3?
    assert_not characters(:ready_v2).v3?
  end

  test "v2? returns true for spec_version 2" do
    assert characters(:ready_v2).v2?
    assert_not characters(:ready_v3).v2?
  end

  # === Data Accessors ===

  test "first_mes returns greeting from data" do
    assert_equal "Hello", characters(:ready_v2).first_mes
  end

  test "alternate_greetings returns array or empty" do
    character = Character.new(
      name: "Test",
      data: { "name" => "Test", "alternate_greetings" => %w[Hi Hello] },
      spec_version: 2
    )
    assert_equal %w[Hi Hello], character.alternate_greetings

    empty_character = Character.new(
      name: "Test",
      data: { "name" => "Test" },
      spec_version: 2
    )
    assert_equal [], empty_character.alternate_greetings
  end

  test "character_book returns lorebook data" do
    character = Character.new(
      name: "Test",
      data: { "name" => "Test", "character_book" => { "name" => "Test Book" } },
      spec_version: 3
    )
    assert_equal({ "name" => "Test Book" }, character.character_book)
  end

  # === Scopes ===

  test "ready scope returns only ready characters" do
    ready_chars = Character.ready
    assert ready_chars.all?(&:ready?)
    assert_includes ready_chars, characters(:ready_v2)
    assert_not_includes ready_chars, characters(:pending_character)
  end

  test "pending scope returns only pending characters" do
    pending_chars = Character.pending
    assert pending_chars.all? { |c| c.status == "pending" }
  end

  test "by_spec_version scope filters by version" do
    v2_chars = Character.by_spec_version(2)
    v3_chars = Character.by_spec_version(3)

    assert v2_chars.all? { |c| c.spec_version == 2 }
    assert v3_chars.all? { |c| c.spec_version == 3 }
  end

  test "with_tag scope filters by tag" do
    fantasy = Character.with_tag("fantasy")

    assert fantasy.exists?(id: characters(:ready_v2).id)
    assert_not fantasy.exists?(id: characters(:ready_v3).id)
  end

  # === Field Extraction ===

  test "extracts searchable fields from data on save" do
    character = Character.create!(
      name: "Initial",
      data: {
        "name" => "Extracted Name",
        "nickname" => "Nick",
        "personality" => "Friendly",
        "tags" => %w[test fantasy],
        "creator_notes_multilingual" => { "en" => "English", "ja" => "日本語" },
      },
      spec_version: 3
    )

    assert_equal "Extracted Name", character.name
    assert_equal "Nick", character.nickname
    assert_equal "Friendly", character.personality
    assert_equal %w[test fantasy], character.tags
    assert_equal %w[en ja], character.supported_languages
  end

  # === Export ===

  test "export_card_hash for v3" do
    character = characters(:ready_v3)
    export = character.export_card_hash

    assert_equal "chara_card_v3", export["spec"]
    assert_equal "3.0", export["spec_version"]
    assert_equal character.data, export["data"]
  end

  test "export_card_hash for v2" do
    character = characters(:ready_v2)
    export = character.export_card_hash

    assert_equal "chara_card_v2", export["spec"]
    assert_equal "2.0", export["spec_version"]
  end

  test "export_card_hash with explicit version conversion" do
    character = characters(:ready_v3)
    export_v2 = character.export_card_hash(version: 2)

    assert_equal "chara_card_v2", export_v2["spec"]
    # V3-only fields should be excluded
    refute export_v2["data"].key?("group_only_greetings")
    refute export_v2["data"].key?("assets")
  end
end
