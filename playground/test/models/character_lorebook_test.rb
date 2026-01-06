# frozen_string_literal: true

require "test_helper"

class CharacterLorebookTest < ActiveSupport::TestCase
  setup do
    @character = characters(:ready_v3)
    @lorebook = Lorebook.create!(name: "Test Lorebook")
    @lorebook2 = Lorebook.create!(name: "Test Lorebook 2")
  end

  teardown do
    @lorebook&.destroy
    @lorebook2&.destroy
  end

  test "valid with all required attributes" do
    link = CharacterLorebook.new(
      character: @character,
      lorebook: @lorebook,
      source: "primary"
    )
    assert link.valid?
  end

  test "requires character" do
    link = CharacterLorebook.new(lorebook: @lorebook, source: "primary")
    assert_not link.valid?
    assert_includes link.errors[:character], "must exist"
  end

  test "requires lorebook" do
    link = CharacterLorebook.new(character: @character, source: "primary")
    assert_not link.valid?
    assert_includes link.errors[:lorebook], "must exist"
  end

  test "source must be primary or additional" do
    link = CharacterLorebook.new(character: @character, lorebook: @lorebook, source: "invalid")
    assert_not link.valid?
    assert_includes link.errors[:source], "is not included in the list"
  end

  test "lorebook can only be linked once per character" do
    CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "additional")
    duplicate = CharacterLorebook.new(character: @character, lorebook: @lorebook, source: "additional")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:lorebook_id], "is already linked to this character"
  end

  test "only one primary lorebook allowed per character" do
    CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "primary")
    second_primary = CharacterLorebook.new(character: @character, lorebook: @lorebook2, source: "primary")
    assert_not second_primary.valid?
    assert_includes second_primary.errors[:source], "can only have one primary lorebook per character"
  end

  test "multiple additional lorebooks allowed per character" do
    first = CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "additional")
    second = CharacterLorebook.new(character: @character, lorebook: @lorebook2, source: "additional")
    assert second.valid?
    assert first.persisted?
  end

  test "enabled scope returns only enabled links" do
    enabled = CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "additional", enabled: true)
    disabled = CharacterLorebook.create!(character: @character, lorebook: @lorebook2, source: "additional", enabled: false)

    result = @character.character_lorebooks.enabled

    assert_includes result, enabled
    assert_not_includes result, disabled
  end

  test "primary scope returns only primary links" do
    primary = CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "primary")
    additional = CharacterLorebook.create!(character: @character, lorebook: @lorebook2, source: "additional")

    result = @character.character_lorebooks.primary

    assert_includes result, primary
    assert_not_includes result, additional
  end

  test "additional scope returns only additional links" do
    primary = CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "primary")
    additional = CharacterLorebook.create!(character: @character, lorebook: @lorebook2, source: "additional")

    result = @character.character_lorebooks.additional

    assert_not_includes result, primary
    assert_includes result, additional
  end

  test "by_priority orders by priority ascending" do
    link1 = CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "additional", priority: 2)
    link2 = CharacterLorebook.create!(character: @character, lorebook: @lorebook2, source: "additional", priority: 1)

    result = @character.character_lorebooks.by_priority.to_a

    assert_equal link2, result.first
    assert_equal link1, result.second
  end

  test "auto-sets priority for new records" do
    link1 = CharacterLorebook.create!(character: @character, lorebook: @lorebook, source: "additional")
    link2 = CharacterLorebook.create!(character: @character, lorebook: @lorebook2, source: "additional")

    assert_equal 0, link1.priority
    assert_equal 1, link2.priority
  end

  test "destroying character destroys character_lorebooks" do
    character = Character.create!(name: "Test Char", status: "ready", spec_version: 3, data: { name: "Test Char" })
    CharacterLorebook.create!(character: character, lorebook: @lorebook, source: "primary")

    assert_difference "CharacterLorebook.count", -1 do
      character.destroy
    end
  end

  test "destroying lorebook destroys character_lorebooks" do
    lorebook = Lorebook.create!(name: "Temp Lorebook")
    CharacterLorebook.create!(character: @character, lorebook: lorebook, source: "primary")

    assert_difference "CharacterLorebook.count", -1 do
      lorebook.destroy
    end
  end
end
