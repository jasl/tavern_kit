# frozen_string_literal: true

require "test_helper"
require_relative "../../../app/services/presets/importer/base"

module Presets
  module Importer
    class DetectorTest < ActiveSupport::TestCase
      setup do
        @user = users(:member)
        @detector = Detector.new
      end

      test "detects TavernKit format by version field" do
        data = {
          tavernkit_preset_version: "1.0",
          name: "TK Preset",
          generation_settings: { temperature: 0.7 },
          preset_settings: { main_prompt: "Hello" },
        }
        file = create_json_file(data, "tk-preset.json")

        result = @detector.call(file, user: @user)

        assert result.success?
        assert_equal "TK Preset", result.preset.name
      end

      test "detects SillyTavern format by chat_completion_source" do
        data = {
          chat_completion_source: "openai",
          temperature: 0.8,
          top_p: 0.9,
          openai_max_tokens: 500,
        }
        file = create_json_file(data, "st-preset.json")

        result = @detector.call(file, user: @user)

        assert result.success?
        assert_equal "St Preset", result.preset.name # from filename
      end

      test "detects SillyTavern format by prompts array" do
        data = {
          prompts: [
            { identifier: "main", content: "Main prompt text" },
          ],
          temperature: 0.8,
        }
        file = create_json_file(data, "st-prompts.json")

        result = @detector.call(file, user: @user)

        assert result.success?
      end

      test "returns failure for invalid JSON" do
        file = StringIO.new("not valid json")
        allow_original_filename(file, "invalid.json")

        result = @detector.call(file, user: @user)

        assert result.failure?
        assert_match(/Invalid JSON format/, result.error)
      end

      test "returns failure for unrecognized format" do
        data = { some_random_field: "value" }
        file = create_json_file(data, "unknown.json")

        result = @detector.call(file, user: @user)

        assert result.failure?
        assert_match(/Unrecognized preset format/, result.error)
      end

      private

      def create_json_file(data, filename)
        content = data.to_json
        file = StringIO.new(content)
        allow_original_filename(file, filename)
        file
      end

      def allow_original_filename(io, filename)
        io.define_singleton_method(:original_filename) { filename }
      end
    end

    class TavernKitImporterTest < ActiveSupport::TestCase
      setup do
        @user = users(:member)
        @importer = TavernKitImporter.new
      end

      test "imports TavernKit preset with all fields" do
        data = {
          "tavernkit_preset_version" => "1.0",
          "name" => "My TK Preset",
          "description" => "Test description",
          "generation_settings" => { "temperature" => 0.7, "top_p" => 0.9 },
          "preset_settings" => { "main_prompt" => "Hello world" },
        }

        result = @importer.call(data, user: @user)

        assert result.success?
        preset = result.preset
        assert_equal "My TK Preset", preset.name
        assert_equal "Test description", preset.description
        assert_equal 0.7, preset.generation_settings.temperature
        assert_equal "Hello world", preset.preset_settings.main_prompt
        assert_equal @user.id, preset.user_id
        assert_equal "private", preset.visibility
      end

      test "uses filename for name when not in JSON" do
        data = {
          "tavernkit_preset_version" => "1.0",
          "generation_settings" => {},
          "preset_settings" => {},
        }

        result = @importer.call(data, user: @user, filename: "my-awesome-preset.json")

        assert result.success?
        assert_equal "My Awesome Preset", result.preset.name
      end

      test "generates unique name when duplicate exists" do
        Preset.create!(name: "Duplicate Test", user: @user, visibility: "private")

        data = {
          "tavernkit_preset_version" => "1.0",
          "name" => "Duplicate Test",
          "generation_settings" => {},
          "preset_settings" => {},
        }

        result = @importer.call(data, user: @user)

        assert result.success?
        assert_equal "Duplicate Test (1)", result.preset.name
      end

      test "returns failure for missing version field" do
        data = { "name" => "No Version" }

        result = @importer.call(data, user: @user)

        assert result.failure?
        assert_match(/missing version field/, result.error)
      end
    end

    class SillyTavernImporterTest < ActiveSupport::TestCase
      setup do
        @user = users(:member)
        @importer = SillyTavernImporter.new
      end

      test "imports SillyTavern preset with generation settings" do
        data = {
          "temperature" => 0.8,
          "top_p" => 0.95,
          "top_k" => 40,
          "openai_max_tokens" => 500,
          "openai_max_context" => 4096,
        }

        result = @importer.call(data, user: @user, filename: "st-preset.json")

        assert result.success?
        preset = result.preset
        assert_equal 0.8, preset.generation_settings.temperature
        assert_equal 0.95, preset.generation_settings.top_p
        assert_equal 40, preset.generation_settings.top_k
        assert_equal 500, preset.generation_settings.max_response_tokens
        assert_equal 4096, preset.generation_settings.max_context_tokens
      end

      test "imports prompts from prompts array" do
        data = {
          "prompts" => [
            { "identifier" => "main", "content" => "Main prompt content" },
            { "identifier" => "jailbreak", "content" => "Jailbreak content" },
            { "identifier" => "nsfw", "content" => "NSFW content" },
            { "identifier" => "enhanceDefinitions", "content" => "Enhance defs" },
          ],
        }

        result = @importer.call(data, user: @user, filename: "prompts.json")

        assert result.success?
        preset = result.preset
        assert_equal "Main prompt content", preset.preset_settings.main_prompt
        assert_equal "Jailbreak content", preset.preset_settings.post_history_instructions
        assert_equal "NSFW content", preset.preset_settings.auxiliary_prompt
        assert_equal "Enhance defs", preset.preset_settings.enhance_definitions
      end

      test "imports direct preset settings" do
        data = {
          "new_chat_prompt" => "[New Chat]",
          "new_group_chat_prompt" => "[New Group]",
          "continue_nudge_prompt" => "[Continue]",
          "group_nudge_prompt" => "[Group Nudge]",
          "wi_format" => "{0}",
          "scenario_format" => "{{scenario}}",
          "personality_format" => "{{personality}}",
        }

        result = @importer.call(data, user: @user, filename: "settings.json")

        assert result.success?
        preset = result.preset
        assert_equal "[New Chat]", preset.preset_settings.new_chat_prompt
        assert_equal "[New Group]", preset.preset_settings.new_group_chat_prompt
        assert_equal "[Continue]", preset.preset_settings.continue_nudge_prompt
        assert_equal "[Group Nudge]", preset.preset_settings.group_nudge_prompt
        assert_equal "{0}", preset.preset_settings.wi_format
      end

      test "skips marker entries in prompts array" do
        data = {
          "prompts" => [
            { "identifier" => "main", "content" => "Main", "marker" => false },
            { "identifier" => "chatHistory", "marker" => true },
            { "identifier" => "jailbreak", "content" => "JB", "marker" => false },
          ],
        }

        result = @importer.call(data, user: @user, filename: "markers.json")

        assert result.success?
        preset = result.preset
        assert_equal "Main", preset.preset_settings.main_prompt
        assert_equal "JB", preset.preset_settings.post_history_instructions
      end

      test "uses filename when name is not provided" do
        data = { "temperature" => 0.7 }

        result = @importer.call(data, user: @user, filename: "my-cool-preset.json")

        assert result.success?
        assert_equal "My Cool Preset", result.preset.name
      end

      test "adds imported from SillyTavern description" do
        data = { "temperature" => 0.7 }

        result = @importer.call(data, user: @user, filename: "test.json")

        assert result.success?
        assert_equal "Imported from SillyTavern", result.preset.description
      end
    end

    class ImportResultTest < ActiveSupport::TestCase
      test "success result" do
        preset = Preset.new(name: "Test")
        result = Presets::Importer::ImportResult.success(preset)

        assert result.success?
        assert_not result.failure?
        assert_equal preset, result.preset
        assert_nil result.error
      end

      test "failure result" do
        result = Presets::Importer::ImportResult.failure("Something went wrong")

        assert result.failure?
        assert_not result.success?
        assert_nil result.preset
        assert_equal "Something went wrong", result.error
      end
    end
  end
end
