# frozen_string_literal: true

require "test_helper"

module CharacterExport
  class BaseTest < ActiveSupport::TestCase
    setup do
      @character = Character.create!(
        name: "Test Character",
        spec_version: 3,
        status: "ready",
        data: {
          name: "Test Character",
          description: "A test character",
          personality: "Friendly",
          first_mes: "Hello!",
          tags: ["test"],
          creator: "Test Creator",
          group_only_greetings: [],
        },
      )
    end

    teardown do
      @character.destroy! if @character.persisted?
    end

    # === Initialization ===

    test "initializes with character" do
      exporter = Base.new(@character)

      assert_equal @character, exporter.character
    end

    test "initializes with options" do
      exporter = Base.new(@character, version: 2, format: :v2_only)

      assert_equal({ version: 2, format: :v2_only }, exporter.options)
    end

    # === Abstract Method ===

    test "call raises NotImplementedError" do
      exporter = Base.new(@character)

      assert_raises(NotImplementedError) { exporter.call }
    end

    # === Card Hash Building ===

    test "builds V3 hash when target version is 3" do
      exporter = Base.new(@character, version: 3)

      hash = exporter.send(:export_card_hash)

      assert_equal "chara_card_v3", hash["spec"]
      assert_equal "3.0", hash["spec_version"]
      assert_equal "Test Character", hash["data"]["name"]
    end

    test "builds V2 hash when target version is 2" do
      exporter = Base.new(@character, version: 2)

      hash = exporter.send(:export_card_hash)

      assert_equal "chara_card_v2", hash["spec"]
      assert_equal "2.0", hash["spec_version"]
      assert_equal "Test Character", hash["data"]["name"]
    end

    test "defaults to character spec_version" do
      @character.spec_version = 2
      exporter = Base.new(@character)

      hash = exporter.send(:export_card_hash)

      assert_equal "chara_card_v2", hash["spec"]
    end

    # === V3 Hash Building ===

    test "V3 hash includes modification_date" do
      exporter = Base.new(@character, version: 3)

      hash = exporter.send(:build_v3_hash)

      assert hash["data"]["modification_date"].present?
      assert_kind_of Integer, hash["data"]["modification_date"]
    end

    test "V3 hash includes assets from character_assets" do
      # Create a blob for the asset
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("test asset content"),
        filename: "emotion.png",
        content_type: "image/png",
      )

      @character.character_assets.create!(
        name: "happy",
        kind: "emotion",
        ext: "png",
        blob: blob,
        content_sha256: Digest::SHA256.hexdigest("test asset content"),
      )

      exporter = Base.new(@character, version: 3)
      hash = exporter.send(:build_v3_hash)

      assert hash["data"]["assets"].present?
      assert_equal 1, hash["data"]["assets"].size
      assert_equal "emotion", hash["data"]["assets"][0]["type"]
      assert_equal "embeded://happy.png", hash["data"]["assets"][0]["uri"]
    end

    # === V2 Hash Building ===

    test "V2 hash includes all standard fields" do
      @character.data = {
        name: "Test",
        description: "Description",
        personality: "Personality",
        scenario: "Scenario",
        first_mes: "First message",
        mes_example: "Example",
        creator_notes: "Notes",
        system_prompt: "System",
        post_history_instructions: "Instructions",
        alternate_greetings: ["Hi"],
        tags: ["tag1"],
        creator: "Creator",
        character_version: "1.0",
        group_only_greetings: [],
      }
      exporter = Base.new(@character, version: 2)

      hash = exporter.send(:build_v2_hash)
      data = hash["data"]

      assert_equal "Test", data["name"]
      assert_equal "Description", data["description"]
      assert_equal "Personality", data["personality"]
      assert_equal "Scenario", data["scenario"]
      assert_equal "First message", data["first_mes"]
      assert_equal "Example", data["mes_example"]
      assert_equal ["Hi"], data["alternate_greetings"]
      assert_equal ["tag1"], data["tags"]
    end

    test "V2 hash includes character_book if present" do
      @character.data = {
        name: "Test",
        group_only_greetings: [],
        character_book: {
          name: "My Lorebook",
          entries: [],
        },
      }
      exporter = Base.new(@character, version: 2)

      hash = exporter.send(:build_v2_hash)

      assert hash["data"]["character_book"].present?
      assert_equal "My Lorebook", hash["data"]["character_book"]["name"]
    end

    test "merged character_book uses data.extensions.world when no primary link exists" do
      lorebook = Lorebook.create!(name: "World Export", visibility: "public")
      lorebook.entries.create!(keys: ["world"], content: "WORLD_EXPORT_ENTRY")

      @character.data = {
        name: "Test Character",
        group_only_greetings: [],
        extensions: { world: "World Export" },
      }

      exporter = Base.new(@character, version: 3)
      merged = exporter.send(:build_merged_character_book)

      assert merged.present?
      assert_equal "World Export", merged["name"]

      entries = merged["entries"]
      assert_kind_of Hash, entries
      assert_equal 1, entries.size
      assert_equal "WORLD_EXPORT_ENTRY", entries.values.first["content"]
    end

    # === Portrait Helpers ===

    test "portrait_content returns nil when no portrait" do
      exporter = Base.new(@character)

      assert_nil exporter.send(:portrait_content)
    end

    test "portrait_content returns content when portrait attached" do
      png_content = File.binread(Rails.root.join("test/fixtures/files/characters/test_character.png"))
      @character.portrait.attach(
        io: StringIO.new(png_content),
        filename: "portrait.png",
        content_type: "image/png",
      )
      exporter = Base.new(@character)

      content = exporter.send(:portrait_content)

      assert content.present?
      assert_equal png_content.bytesize, content.bytesize
    end

    test "portrait_filename returns default when no portrait" do
      exporter = Base.new(@character)

      assert_equal "portrait.png", exporter.send(:portrait_filename)
    end

    test "portrait_extension returns default when no portrait" do
      exporter = Base.new(@character)

      assert_equal "png", exporter.send(:portrait_extension)
    end

    test "portrait_extension returns actual extension when portrait attached" do
      @character.portrait.attach(
        io: StringIO.new("fake jpg content"),
        filename: "portrait.jpg",
        content_type: "image/jpeg",
      )
      exporter = Base.new(@character)

      assert_equal "jpg", exporter.send(:portrait_extension)
    end
  end
end
