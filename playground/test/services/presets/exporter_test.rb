# frozen_string_literal: true

require "test_helper"

module Presets
  class ExporterTest < ActiveSupport::TestCase
    setup do
      @preset = Preset.create!(
        name: "Test Preset",
        description: "A test preset",
        user: users(:member),
        visibility: "private",
        generation_settings: { temperature: 0.8, max_response_tokens: 500 },
        preset_settings: { main_prompt: "Test prompt", post_history_instructions: "Test PHI" }
      )
      @exporter = Exporter.new
    end

    test "exports preset to JSON string" do
      json = @exporter.call(@preset)
      data = JSON.parse(json)

      assert_equal "1.0", data["tavernkit_preset_version"]
      assert_equal "Test Preset", data["name"]
      assert_equal "A test preset", data["description"]
      assert_not_nil data["exported_at"]
    end

    test "exports generation_settings" do
      json = @exporter.call(@preset)
      data = JSON.parse(json)

      assert_equal 0.8, data["generation_settings"]["temperature"]
      assert_equal 500, data["generation_settings"]["max_response_tokens"]
    end

    test "exports preset_settings" do
      json = @exporter.call(@preset)
      data = JSON.parse(json)

      assert_equal "Test prompt", data["preset_settings"]["main_prompt"]
      assert_equal "Test PHI", data["preset_settings"]["post_history_instructions"]
    end

    test "to_hash returns a hash instead of JSON" do
      hash = @exporter.to_hash(@preset)

      assert_kind_of Hash, hash
      assert_equal "1.0", hash[:tavernkit_preset_version]
      assert_equal "Test Preset", hash[:name]
    end

    test "handles preset with nil description" do
      @preset.update!(description: nil)
      json = @exporter.call(@preset)
      data = JSON.parse(json)

      assert_nil data["description"]
    end

    test "handles preset with default settings" do
      # When settings are empty hash, they get defaults from the schema
      @preset.update!(generation_settings: {}, preset_settings: {})
      json = @exporter.call(@preset)
      data = JSON.parse(json)

      # Should still export successfully with default values
      assert data["generation_settings"].is_a?(Hash)
      assert data["preset_settings"].is_a?(Hash)
    end
  end
end
