# frozen_string_literal: true

require "test_helper"
require "json"
require "tempfile"
require "fileutils"

class PngWriterTest < Minitest::Test
  TMP_DIR = File.expand_path("../tmp", __dir__)
  FIXTURES_DIR = File.expand_path("fixtures", __dir__)

  def setup
    FileUtils.mkdir_p(TMP_DIR)
    @test_png = File.join(TMP_DIR, "The-Game-Master-aicharactercards.com_.png")
    skip "Test PNG not available" unless File.exist?(@test_png)
  end

  # --- Writer Module Tests ---

  def test_embed_character_with_both_formats
    character = create_test_character
    output_path = temp_output_path("both")

    TavernKit::Png::Writer.embed_character(@test_png, output_path, character, format: :both)

    assert File.exist?(output_path)

    # Read back and verify both chunks exist
    chunks = TavernKit::Png::Parser.extract_text_chunks(output_path)
    keywords = chunks.map { |c| c[:keyword].downcase }

    assert_includes keywords, "chara", "Should have V2 chara chunk"
    assert_includes keywords, "ccv3", "Should have V3 ccv3 chunk"
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_embed_character_v2_only
    character = create_test_character
    output_path = temp_output_path("v2only")

    TavernKit::Png::Writer.embed_character(@test_png, output_path, character, format: :v2_only)

    assert File.exist?(output_path)

    chunks = TavernKit::Png::Parser.extract_text_chunks(output_path)
    keywords = chunks.map { |c| c[:keyword].downcase }

    assert_includes keywords, "chara", "Should have V2 chara chunk"
    refute_includes keywords, "ccv3", "Should NOT have V3 ccv3 chunk"
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_embed_character_v3_only
    character = create_test_character
    output_path = temp_output_path("v3only")

    TavernKit::Png::Writer.embed_character(@test_png, output_path, character, format: :v3_only)

    assert File.exist?(output_path)

    chunks = TavernKit::Png::Parser.extract_text_chunks(output_path)
    keywords = chunks.map { |c| c[:keyword].downcase }

    refute_includes keywords, "chara", "Should NOT have V2 chara chunk"
    assert_includes keywords, "ccv3", "Should have V3 ccv3 chunk"
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_round_trip_v2_data_integrity
    original_character = create_test_character
    output_path = temp_output_path("roundtrip_v2")

    TavernKit::Png::Writer.embed_character(@test_png, output_path, original_character, format: :v2_only)

    # Load back the character
    loaded_character = TavernKit::CharacterCard.load(output_path)

    # Verify key fields match
    assert_equal original_character.data.name, loaded_character.data.name
    assert_equal original_character.data.description, loaded_character.data.description
    assert_equal original_character.data.personality, loaded_character.data.personality
    assert_equal original_character.data.scenario, loaded_character.data.scenario
    assert_equal original_character.data.first_mes, loaded_character.data.first_mes
    assert_equal original_character.data.creator, loaded_character.data.creator
    assert_equal original_character.data.tags, loaded_character.data.tags
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_round_trip_v3_data_integrity
    original_character = create_test_character_v3
    output_path = temp_output_path("roundtrip_v3")

    TavernKit::Png::Writer.embed_character(@test_png, output_path, original_character, format: :v3_only)

    # Load back the character
    loaded_character = TavernKit::CharacterCard.load(output_path)

    # Verify V3-specific fields
    assert_equal original_character.data.name, loaded_character.data.name
    assert_equal original_character.data.nickname, loaded_character.data.nickname
    assert_equal original_character.data.group_only_greetings, loaded_character.data.group_only_greetings
    assert_equal original_character.data.creation_date, loaded_character.data.creation_date
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_round_trip_both_formats_prefers_v3
    original_character = create_test_character_v3
    output_path = temp_output_path("roundtrip_both")

    TavernKit::Png::Writer.embed_character(@test_png, output_path, original_character, format: :both)

    # Parser should prefer ccv3 over chara
    loaded_character = TavernKit::CharacterCard.load(output_path)

    # Should load V3 data (ccv3 is preferred)
    assert_equal :v3, loaded_character.source_version
    assert_equal original_character.data.nickname, loaded_character.data.nickname
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_replaces_existing_character_chunks
    # First, embed a character
    first_character = TavernKit::Character.create(
      name: "FirstCharacter",
      description: "First description"
    )
    intermediate_path = temp_output_path("intermediate")
    TavernKit::Png::Writer.embed_character(@test_png, intermediate_path, first_character, format: :both)

    # Now embed a different character into the result
    second_character = TavernKit::Character.create(
      name: "SecondCharacter",
      description: "Second description"
    )
    final_path = temp_output_path("final")
    TavernKit::Png::Writer.embed_character(intermediate_path, final_path, second_character, format: :both)

    # Should have the second character, not the first
    loaded = TavernKit::CharacterCard.load(final_path)
    assert_equal "SecondCharacter", loaded.data.name
    assert_equal "Second description", loaded.data.description

    # Should only have one set of character chunks
    chunks = TavernKit::Png::Parser.extract_text_chunks(final_path)
    chara_chunks = chunks.select { |c| c[:keyword].downcase == "chara" }
    ccv3_chunks = chunks.select { |c| c[:keyword].downcase == "ccv3" }

    assert_equal 1, chara_chunks.size, "Should have exactly one chara chunk"
    assert_equal 1, ccv3_chunks.size, "Should have exactly one ccv3 chunk"
  ensure
    FileUtils.rm_f(intermediate_path) if intermediate_path
    FileUtils.rm_f(final_path) if final_path
  end

  def test_invalid_format_raises_error
    character = create_test_character
    output_path = temp_output_path("invalid")

    assert_raises(ArgumentError) do
      TavernKit::Png::Writer.embed_character(@test_png, output_path, character, format: :invalid)
    end
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_nonexistent_input_raises_error
    character = create_test_character
    output_path = temp_output_path("nonexistent")

    assert_raises(TavernKit::Png::WriteError) do
      TavernKit::Png::Writer.embed_character("/nonexistent/path.png", output_path, character)
    end
  end

  def test_invalid_png_raises_error
    character = create_test_character
    output_path = temp_output_path("invalid_png")

    # Create a non-PNG file
    invalid_input = temp_output_path("not_a_png")
    File.write(invalid_input, "This is not a PNG file")

    assert_raises(TavernKit::Png::ParseError) do
      TavernKit::Png::Writer.embed_character(invalid_input, output_path, character)
    end
  ensure
    FileUtils.rm_f(invalid_input) if invalid_input
    FileUtils.rm_f(output_path) if output_path
  end

  # --- CharacterCard.write_to_png Tests ---

  def test_character_card_write_to_png
    character = create_test_character
    output_path = temp_output_path("api_test")

    TavernKit::CharacterCard.write_to_png(
      character,
      input_png: @test_png,
      output_png: output_path,
      format: :both
    )

    assert File.exist?(output_path)

    loaded = TavernKit::CharacterCard.load(output_path)
    assert_equal character.data.name, loaded.data.name
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_character_card_write_to_png_default_format
    character = create_test_character
    output_path = temp_output_path("api_default")

    # Should default to :both
    TavernKit::CharacterCard.write_to_png(
      character,
      input_png: @test_png,
      output_png: output_path
    )

    chunks = TavernKit::Png::Parser.extract_text_chunks(output_path)
    keywords = chunks.map { |c| c[:keyword].downcase }

    assert_includes keywords, "chara"
    assert_includes keywords, "ccv3"
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  # --- Helper Methods ---

  private

  def create_test_character
    TavernKit::Character.create(
      name: "TestCharacter",
      description: "A test character for PNG writer tests.",
      personality: "Friendly and helpful",
      scenario: "Testing the PNG writer functionality",
      first_mes: "Hello! I'm a test character.",
      mes_example: "{{user}}: Hi!\n{{char}}: Hello there!",
      creator: "TavernKit Tests",
      tags: ["test", "png-writer"],
      system_prompt: "You are TestCharacter.",
      post_history_instructions: "Stay in character."
    )
  end

  def create_test_character_v3
    TavernKit::Character.create(
      name: "V3TestCharacter",
      description: "A V3 test character.",
      personality: "Advanced and modern",
      nickname: "V3Test",
      group_only_greetings: ["Hello group!", "Team, assemble!"],
      creation_date: 1703462400,
      modification_date: 1703548800,
      source: ["https://example.com/test"],
      creator: "TavernKit Tests",
      tags: ["test", "v3"]
    )
  end

  def temp_output_path(suffix)
    File.join(TMP_DIR, "png_writer_test_#{suffix}_#{Time.now.to_i}_#{rand(1000)}.png")
  end
end
