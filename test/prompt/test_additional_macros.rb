# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestAdditionalMacros < Minitest::Test
      # Test card with all fields populated for macro testing
      def card_with_all_fields
        CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Oracle",
            "description" => "A wise oracle who lives in a crystal tower.",
            "personality" => "Mysterious, kind, prophetic",
            "scenario" => "You seek guidance from the oracle.",
            "first_mes" => "Welcome, traveler.",
            "mes_example" => "<START>\n{{user}}: What does the future hold?\n{{char}}: The mists of time reveal many paths...\n<START>\n{{user}}: Tell me more.\n{{char}}: Patience, seeker.",
            "system_prompt" => "You are {{char}}, a mystical oracle.",
            "post_history_instructions" => "Speak in riddles and prophecies.",
          },
        })
      end

      def minimal_card
        CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Minimal",
          },
        })
      end

      def user
        User.new(name: "Traveler", persona: "A curious adventurer")
      end

      def preset_with_macros(template)
        Preset.new(
          main_prompt: template,
          post_history_instructions: "",
          prefer_char_prompt: false,
          prefer_char_instructions: false,
        )
      end

      # --- {{charPrompt}} Tests ---

      def test_charprompt_expands_to_system_prompt
        preset = preset_with_macros("Main: {{charPrompt}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        main_prompt = plan.messages.first.content
        # {{charPrompt}} expands to the system_prompt field, and nested macros are expanded
        # by subsequent passes (ST-like behavior).
        assert_equal "Main: You are Oracle, a mystical oracle.", main_prompt
      end

      def test_charprompt_empty_when_no_system_prompt
        preset = preset_with_macros("Main: [{{charPrompt}}]")
        plan = TavernKit.build(character: minimal_card, user: user, preset: preset, message: "Hello")

        main_prompt = plan.messages.first.content
        assert_equal "Main: []", main_prompt
      end

      def test_charprompt_is_case_insensitive
        preset = preset_with_macros("{{CHARPROMPT}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        assert_equal "You are Oracle, a mystical oracle.", plan.messages.first.content
      end

      # --- {{charJailbreak}} / {{charInstruction}} Tests ---

      def test_charjailbreak_expands_to_post_history_instructions
        preset = preset_with_macros("{{charJailbreak}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        assert_equal "Speak in riddles and prophecies.", plan.messages.first.content
      end

      def test_charinstruction_expands_to_post_history_instructions
        preset = preset_with_macros("{{charInstruction}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        assert_equal "Speak in riddles and prophecies.", plan.messages.first.content
      end

      def test_charjailbreak_and_charinstruction_are_aliases
        preset1 = preset_with_macros("{{charJailbreak}}")
        preset2 = preset_with_macros("{{charInstruction}}")

        plan1 = TavernKit.build(character: card_with_all_fields, user: user, preset: preset1, message: "Hello")
        plan2 = TavernKit.build(character: card_with_all_fields, user: user, preset: preset2, message: "Hello")

        assert_equal plan1.messages.first.content, plan2.messages.first.content
      end

      def test_charjailbreak_empty_when_no_phi
        preset = preset_with_macros("[{{charJailbreak}}]")
        plan = TavernKit.build(character: minimal_card, user: user, preset: preset, message: "Hello")

        assert_equal "[]", plan.messages.first.content
      end

      # --- {{mesExamplesRaw}} Tests ---

      def test_mesexamplesraw_returns_raw_mes_example
        preset = preset_with_macros("{{mesExamplesRaw}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        raw = plan.messages.first.content
        # Preserves the raw blocks while still participating in macro expansion (ST-like behavior).
        assert_includes raw, "<START>"
        assert_includes raw, "Traveler: What does the future hold?"
        assert_includes raw, "Oracle: The mists of time reveal many paths..."
      end

      def test_mesexamplesraw_empty_when_no_mes_example
        preset = preset_with_macros("[{{mesExamplesRaw}}]")
        plan = TavernKit.build(character: minimal_card, user: user, preset: preset, message: "Hello")

        assert_equal "[]", plan.messages.first.content
      end

      # --- {{mesExamples}} Tests ---

      def test_mesexamples_returns_formatted_examples
        preset = preset_with_macros("{{mesExamples}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        formatted = plan.messages.first.content
        # ST-like normalization: <START> blocks and macro expansion for {{user}}/{{char}}.
        assert_includes formatted, "<START>"
        assert_includes formatted, "Traveler: What does the future hold?"
        assert_includes formatted, "Oracle: The mists of time reveal many paths..."
      end

      def test_mesexamples_empty_when_no_mes_example
        preset = preset_with_macros("[{{mesExamples}}]")
        plan = TavernKit.build(character: minimal_card, user: user, preset: preset, message: "Hello")

        assert_equal "[]", plan.messages.first.content
      end

      def test_mesexamples_formats_multiple_blocks
        preset = preset_with_macros("{{mesExamples}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        formatted = plan.messages.first.content
        # Should have two <START> markers (one for each block)
        assert_equal 2, formatted.scan("<START>").count
      end

      # --- {{personality}} Tests ---

      def test_personality_expands_to_personality_field
        preset = preset_with_macros("{{personality}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        assert_equal "Mysterious, kind, prophetic", plan.messages.first.content
      end

      def test_personality_empty_when_no_personality
        preset = preset_with_macros("[{{personality}}]")
        plan = TavernKit.build(character: minimal_card, user: user, preset: preset, message: "Hello")

        assert_equal "[]", plan.messages.first.content
      end

      # --- Combined Macro Tests ---

      def test_multiple_additional_macros_in_same_template
        preset = preset_with_macros("Prompt: {{charPrompt}} | PHI: {{charJailbreak}} | Personality: {{personality}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        result = plan.messages.first.content
        assert_includes result, "Prompt: You are Oracle, a mystical oracle."
        assert_includes result, "PHI: Speak in riddles and prophecies."
        assert_includes result, "Personality: Mysterious, kind, prophetic"
      end

      def test_additional_macros_work_with_existing_macros
        preset = preset_with_macros("{{char}} says: {{charPrompt}} to {{user}}")
        plan = TavernKit.build(character: card_with_all_fields, user: user, preset: preset, message: "Hello")

        result = plan.messages.first.content
        assert_equal "Oracle says: You are Oracle, a mystical oracle. to Traveler", result
      end

      # --- Macro Expansion in Character Card Fields ---

      def test_macros_expand_in_description_block
        card = CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Guide",
            "description" => "{{char}} helps {{user}} on their journey.",
            "personality" => "Wise and patient",
          },
        })

        preset = Preset.new(main_prompt: "System", prefer_char_prompt: false)
        plan = TavernKit.build(character: card, user: user, preset: preset, message: "Hello")

        desc_block = plan.blocks.find { |b| b.slot == :character_description }
        refute_nil desc_block
        assert_includes desc_block.content, "Guide helps Traveler on their journey."
      end

      def test_macros_expand_in_scenario_block
        card = CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Guide",
            "scenario" => "{{user}} meets {{char}} at the crossroads.",
          },
        })

        preset = Preset.new(main_prompt: "System", prefer_char_prompt: false)
        plan = TavernKit.build(character: card, user: user, preset: preset, message: "Hello")

        scenario_block = plan.blocks.find { |b| b.slot == :scenario }
        refute_nil scenario_block
        assert_includes scenario_block.content, "Traveler meets Guide at the crossroads."
      end

      # --- Format Helper Tests ---

      def test_format_mes_examples_handles_single_block
        card = CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Test",
            "mes_example" => "<START>\n{{user}}: Hello\n{{char}}: Hi there!",
          },
        })

        preset = preset_with_macros("{{mesExamples}}")
        plan = TavernKit.build(character: card, user: user, preset: preset, message: "Test")

        result = plan.messages.first.content
        assert_equal 1, result.scan("<START>").count
        assert_includes result, "Traveler: Hello"
        assert_includes result, "Test: Hi there!"
      end

      def test_format_mes_examples_handles_multiline_messages
        card = CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Test",
            "mes_example" => "<START>\n{{user}}: Line 1\nLine 2\n{{char}}: Response",
          },
        })

        preset = preset_with_macros("{{mesExamples}}")
        plan = TavernKit.build(character: card, user: user, preset: preset, message: "Test")

        result = plan.messages.first.content
        assert_includes result, "Traveler: Line 1\nLine 2"
        assert_includes result, "Test: Response"
      end

      def test_format_mes_examples_handles_empty_string
        card = CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Test",
            "mes_example" => "",
          },
        })

        preset = preset_with_macros("[{{mesExamples}}]")
        plan = TavernKit.build(character: card, user: user, preset: preset, message: "Test")

        assert_equal "[]", plan.messages.first.content
      end

      def test_format_mes_examples_handles_whitespace_only
        card = CharacterCard.load({
          "spec" => "chara_card_v2",
          "spec_version" => "2.0",
          "data" => {
            "name" => "Test",
            "mes_example" => "   \n  \n  ",
          },
        })

        preset = preset_with_macros("[{{mesExamples}}]")
        plan = TavernKit.build(character: card, user: user, preset: preset, message: "Test")

        assert_equal "[]", plan.messages.first.content
      end
    end
  end
end
