# frozen_string_literal: true

require "test_helper"

class CharacterAssetTest < ActiveSupport::TestCase
  fixtures :characters

  setup do
    @character = characters(:ready_v2)
    # Create a blob for testing
    @blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("test content"),
      filename: "test.png",
      content_type: "image/png"
    )
  end

  # === Validations ===

  test "valid with all required attributes" do
    asset = CharacterAsset.new(
      character: @character,
      blob: @blob,
      name: "test_asset",
      kind: "icon"
    )
    assert asset.valid?
  end

  test "invalid without character" do
    asset = CharacterAsset.new(
      blob: @blob,
      name: "test",
      kind: "icon"
    )
    assert_not asset.valid?
    assert_includes asset.errors[:character], "must exist"
  end

  test "invalid without blob" do
    asset = CharacterAsset.new(
      character: @character,
      name: "test",
      kind: "icon"
    )
    assert_not asset.valid?
    assert_includes asset.errors[:blob], "must exist"
  end

  test "invalid without name" do
    asset = CharacterAsset.new(
      character: @character,
      blob: @blob,
      kind: "icon"
    )
    assert_not asset.valid?
    assert_includes asset.errors[:name], "can't be blank"
  end

  test "invalid with unsupported kind" do
    asset = CharacterAsset.new(
      character: @character,
      blob: @blob,
      name: "test",
      kind: "unknown"
    )
    assert_not asset.valid?
    assert_includes asset.errors[:kind], "is not included in the list"
  end

  test "name must be unique per character" do
    CharacterAsset.create!(
      character: @character,
      blob: @blob,
      name: "unique_name",
      kind: "icon"
    )

    duplicate = CharacterAsset.new(
      character: @character,
      blob: @blob,
      name: "unique_name",
      kind: "emotion"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "same name allowed for different characters" do
    other_character = characters(:ready_v3)

    CharacterAsset.create!(
      character: @character,
      blob: @blob,
      name: "shared_name",
      kind: "icon"
    )

    other_asset = CharacterAsset.new(
      character: other_character,
      blob: @blob,
      name: "shared_name",
      kind: "icon"
    )
    assert other_asset.valid?
  end

  # === Scopes ===

  test "kind scopes filter correctly" do
    %w[icon emotion background user_icon].each do |kind|
      CharacterAsset.create!(
        character: @character,
        blob: @blob,
        name: "test_#{kind}",
        kind: kind
      )
    end

    assert CharacterAsset.icons.all? { |a| a.kind == "icon" }
    assert CharacterAsset.emotions.all? { |a| a.kind == "emotion" }
    assert CharacterAsset.backgrounds.all? { |a| a.kind == "background" }
    assert CharacterAsset.user_icons.all? { |a| a.kind == "user_icon" }
  end

  # === Methods ===

  test "main_icon? returns true for main icon" do
    main_icon = CharacterAsset.new(kind: "icon", name: "main")
    assert main_icon.main_icon?

    other_icon = CharacterAsset.new(kind: "icon", name: "happy")
    assert_not other_icon.main_icon?

    emotion = CharacterAsset.new(kind: "emotion", name: "main")
    assert_not emotion.main_icon?
  end

  test "url returns blob path" do
    asset = CharacterAsset.create!(
      character: @character,
      blob: @blob,
      name: "url_test",
      kind: "icon"
    )

    url = asset.url
    assert_includes url, "rails/active_storage/blobs"
  end
end
