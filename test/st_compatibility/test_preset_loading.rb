# frozen_string_literal: true

require "test_helper"

module TavernKit
  module STCompatibility
    # Tests for loading SillyTavern preset JSON files.
    class TestPresetLoading < Minitest::Test
      # Test: Basic ST preset JSON loading
      def test_basic_st_preset_loading
        st_json = {
          "prompts" => [
            { "identifier" => "main", "content" => "You are a helpful assistant." },
            { "identifier" => "jailbreak", "content" => "Stay in character at all times." },
          ],
          "new_example_chat_prompt" => "[Example]",
          "openai_max_context" => 8192,
          "openai_max_tokens" => 1024,
        }

        preset = Preset.from_st_preset_json(st_json)

        assert_equal "You are a helpful assistant.", preset.main_prompt
        assert_equal "Stay in character at all times.", preset.post_history_instructions
        assert_equal "[Example]", preset.new_example_chat
        assert_equal 8192, preset.context_window_tokens
        assert_equal 1024, preset.reserved_response_tokens
      end

      def test_group_nudge_prompt_field_is_loaded
        st_json = {
          "group_nudge_prompt" => "NUDGE {{char}}",
        }

        preset = Preset.from_st_preset_json(st_json)
        assert_equal "NUDGE {{char}}", preset.group_nudge_prompt
      end

      # Test: ST preset with prompts array
      def test_st_preset_with_prompts_array
        st_json = {
          "prompts" => [
            { "identifier" => "main", "enabled" => true },
            { "identifier" => "charDescription", "enabled" => true },
            { "identifier" => "chatHistory", "enabled" => true },
            { "identifier" => "jailbreak", "enabled" => true },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        refute_nil entries
        assert_equal 4, entries.length

        # Check ID normalization
        ids = entries.map(&:id)
        assert_includes ids, "main_prompt"
        assert_includes ids, "character_description"
        assert_includes ids, "chat_history"
        assert_includes ids, "post_history_instructions"
      end

      # Test: ST preset with prompt_order (takes precedence)
      def test_st_preset_prompt_order_takes_precedence
        st_json = {
          "prompts" => [
            { "identifier" => "main", "enabled" => true },
            { "identifier" => "charDescription", "enabled" => true },
            { "identifier" => "jailbreak", "enabled" => true },
          ],
          # prompt_order defines different order and disabled state
          "prompt_order" => [
            { "identifier" => "charDescription", "enabled" => false },
            { "identifier" => "main", "enabled" => true },
            { "identifier" => "jailbreak", "enabled" => true },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        refute_nil entries

        # Order should follow prompt_order
        assert_equal "character_description", entries[0].id
        assert_equal "main_prompt", entries[1].id
        assert_equal "post_history_instructions", entries[2].id

        # Enabled state from prompt_order
        refute entries[0].enabled?, "charDescription should be disabled per prompt_order"
        assert entries[1].enabled?, "main should be enabled"
      end

      # Test: ST preset with injection settings
      def test_st_preset_with_injection_settings
        st_json = {
          "prompts" => [
            {
              "identifier" => "customPrompt",
              "name" => "My Custom Prompt",
              "content" => "Custom content here",
              "role" => 0, # system
              "injection_position" => 1, # in_chat
              "injection_depth" => 2,
              "injection_order" => 50,
              "enabled" => true,
            },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        custom = entries.find { |e| e.id == "customPrompt" }
        refute_nil custom

        assert_equal "My Custom Prompt", custom.name
        assert_equal "Custom content here", custom.content
        assert_equal :system, custom.role
        assert_equal :in_chat, custom.position
        assert_equal 2, custom.depth
        assert_equal 50, custom.order
        assert custom.enabled?
        refute custom.pinned?
      end

      # Test: injection_depth=0 is valid (depth=0 inserts after last message) and must not be overridden.
      def test_st_preset_injection_depth_zero_is_preserved
        st_json = {
          "prompts" => [
            {
              "identifier" => "customDepthZero",
              "content" => "Custom content here",
              "role" => 0, # system
              "injection_position" => 1, # in_chat
              "injection_depth" => 0,
              "enabled" => true,
            },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        custom = entries.find { |e| e.id == "customDepthZero" }
        refute_nil custom

        assert_equal :in_chat, custom.position
        assert_equal 0, custom.depth
      end

      # Test: ST preset role normalization
      def test_st_preset_role_normalization
        st_json = {
          "prompts" => [
            { "identifier" => "sys", "role" => 0 },
            { "identifier" => "usr", "role" => 1 },
            { "identifier" => "ast", "role" => 2 },
            { "identifier" => "sysStr", "role" => "system" },
            { "identifier" => "usrStr", "role" => "user" },
            { "identifier" => "astStr", "role" => "assistant" },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        assert_equal :system, entries.find { |e| e.id == "sys" }.role
        assert_equal :user, entries.find { |e| e.id == "usr" }.role
        assert_equal :assistant, entries.find { |e| e.id == "ast" }.role
        assert_equal :system, entries.find { |e| e.id == "sysStr" }.role
        assert_equal :user, entries.find { |e| e.id == "usrStr" }.role
        assert_equal :assistant, entries.find { |e| e.id == "astStr" }.role
      end

      # Test: ST preset with character preference flags
      def test_st_preset_character_preference_flags
        st_json = {
          "prefer_character_prompt" => false,
          "prefer_character_jailbreak" => false,
        }

        preset = Preset.from_st_preset_json(st_json)

        refute preset.prefer_char_prompt
        refute preset.prefer_char_instructions
      end

      # Test: Empty prompts returns nil (uses defaults)
      def test_empty_prompts_uses_defaults
        st_json = {
          "prompts" => [],
        }

        preset = Preset.from_st_preset_json(st_json)

        # Should return nil, which means effective_prompt_entries will use defaults
        assert_nil preset.prompt_entries
        refute_nil preset.effective_prompt_entries
      end

      def test_st_preset_parses_prompting_settings_fields
        st_json = {
          "squash_system_messages" => true,
          "continue_prefill" => true,
          # Accept numeric codes for continue_postfix (0..3)
          "continue_postfix" => 3,
        }

        preset = Preset.from_st_preset_json(st_json)

        assert preset.squash_system_messages
        assert preset.continue_prefill
        assert_equal "\n\n", preset.continue_postfix
      end

      # Test: Pinned identifiers are correctly marked
      def test_pinned_identifiers_marked_correctly
        st_json = {
          "prompts" => [
            { "identifier" => "main" },
            { "identifier" => "worldInfoBefore" },
            { "identifier" => "personaDescription" },
            { "identifier" => "charDescription" },
            { "identifier" => "chatHistory" },
            { "identifier" => "jailbreak" },
            { "identifier" => "customNonPinned", "content" => "custom" },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        # ST built-in markers should be pinned
        assert entries.find { |e| e.id == "main_prompt" }.pinned?
        assert entries.find { |e| e.id == "world_info_before_char_defs" }.pinned?
        assert entries.find { |e| e.id == "persona_description" }.pinned?
        assert entries.find { |e| e.id == "character_description" }.pinned?
        assert entries.find { |e| e.id == "chat_history" }.pinned?
        assert entries.find { |e| e.id == "post_history_instructions" }.pinned?

        # Custom prompts should not be pinned
        refute entries.find { |e| e.id == "customNonPinned" }.pinned?
      end

      # ─────────────────────────────────────────────────────────────────
      # P0-1: Nested prompt_order structure (character_id + order)
      # ─────────────────────────────────────────────────────────────────

      # Test: prompt_order with nested structure (character_id + order)
      def test_nested_prompt_order_structure
        st_json = {
          "prompts" => [
            { "identifier" => "main", "enabled" => true },
            { "identifier" => "charDescription", "enabled" => true },
            { "identifier" => "jailbreak", "enabled" => true },
          ],
          # Nested format: character_id 100000 is the global/default bucket
          "prompt_order" => [
            {
              "character_id" => 100_000,
              "order" => [
                { "identifier" => "charDescription", "enabled" => false },
                { "identifier" => "main", "enabled" => true },
                { "identifier" => "jailbreak", "enabled" => true },
              ],
            },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        refute_nil entries
        assert_equal 3, entries.length

        # Order should follow the nested prompt_order
        assert_equal "character_description", entries[0].id
        assert_equal "main_prompt", entries[1].id
        assert_equal "post_history_instructions", entries[2].id

        # Enabled state from prompt_order
        refute entries[0].enabled?, "charDescription should be disabled per nested prompt_order"
        assert entries[1].enabled?, "main should be enabled"
      end

      # Test: Nested prompt_order with multiple character buckets uses global (100000)
      def test_nested_prompt_order_prefers_global_bucket
        st_json = {
          "prompts" => [
            { "identifier" => "main" },
            { "identifier" => "charDescription" },
          ],
          "prompt_order" => [
            {
              "character_id" => 12345, # specific character
              "order" => [
                { "identifier" => "main", "enabled" => false },
                { "identifier" => "charDescription", "enabled" => true },
              ],
            },
            {
              "character_id" => 100_000, # global bucket
              "order" => [
                { "identifier" => "charDescription", "enabled" => false },
                { "identifier" => "main", "enabled" => true },
              ],
            },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        # Should use global bucket (100000), not the character-specific one
        assert_equal "character_description", entries[0].id
        assert_equal "main_prompt", entries[1].id

        # Enabled state from global bucket
        refute entries[0].enabled?, "charDescription should be disabled per global bucket"
        assert entries[1].enabled?, "main should be enabled per global bucket"
      end

      # ─────────────────────────────────────────────────────────────────
      # P0-2: Fix system_prompt => pinned misclassification
      # ─────────────────────────────────────────────────────────────────

      # Test: Unknown prompts with system_prompt=true should NOT be marked as pinned
      def test_unknown_system_prompt_not_pinned
        st_json = {
          "prompts" => [
            # Known ST identifier - should be pinned
            { "identifier" => "main", "system_prompt" => true },
            # Unknown identifier with system_prompt=true - should NOT be pinned
            { "identifier" => "newFutureSTPrompt", "system_prompt" => true, "content" => "some future feature" },
            # Custom prompt without system_prompt flag - should not be pinned
            { "identifier" => "userCustom", "content" => "user defined" },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        entries = preset.prompt_entries

        main_entry = entries.find { |e| e.id == "main_prompt" }
        future_entry = entries.find { |e| e.id == "newFutureSTPrompt" }
        custom_entry = entries.find { |e| e.id == "userCustom" }

        # Known ID should be pinned
        assert main_entry.pinned?, "Known ST identifier 'main' should be pinned"

        # Unknown ID with system_prompt=true should NOT be pinned (to preserve data)
        refute future_entry.pinned?, "Unknown identifier with system_prompt=true should NOT be pinned"
        assert_equal "some future feature", future_entry.content, "Content should be preserved"

        # Regular custom prompt should not be pinned
        refute custom_entry.pinned?, "Custom prompt should not be pinned"
      end

      # ─────────────────────────────────────────────────────────────────
      # Core prompt content (Prompt Manager prompts[])
      # ─────────────────────────────────────────────────────────────────

      def test_main_prompt_read_from_prompts_array
        st_json = {
          "prompts" => [
            { "identifier" => "main", "content" => "System prompt from prompts array" },
            { "identifier" => "charDescription" },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)

        assert_equal "System prompt from prompts array", preset.main_prompt
      end

      def test_jailbreak_read_from_prompts_array
        st_json = {
          "prompts" => [
            { "identifier" => "main" },
            { "identifier" => "jailbreak", "content" => "PHI from prompts array" },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)

        assert_equal "PHI from prompts array", preset.post_history_instructions
      end

      def test_legacy_prompt_fields_are_ignored_in_st_preset_json
        st_json = {
          "main_prompt" => "LEGACY_MAIN",
          "jailbreak_prompt" => "LEGACY_PHI",
          "nsfw_prompt" => "LEGACY_AUX",
          "prompts" => [
            { "identifier" => "main", "content" => "MAIN_FROM_PROMPTS" },
            { "identifier" => "jailbreak", "content" => "PHI_FROM_PROMPTS" },
            { "identifier" => "nsfw", "content" => "AUX_FROM_PROMPTS" },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)

        assert_equal "MAIN_FROM_PROMPTS", preset.main_prompt
        assert_equal "PHI_FROM_PROMPTS", preset.post_history_instructions
        assert_equal "AUX_FROM_PROMPTS", preset.auxiliary_prompt
      end

      # Test: Default main prompt used when both top-level and prompts[] are empty
      def test_default_main_prompt_when_all_empty
        st_json = {
          # No main_prompt at all
          "prompts" => [
            { "identifier" => "main", "content" => "" },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)

        # Should use DEFAULT_MAIN_PROMPT
        assert_equal TavernKit::Preset::DEFAULT_MAIN_PROMPT, preset.main_prompt
      end
    end
  end
end
