# frozen_string_literal: true

require "test_helper"

class PresetStImporterTest < Minitest::Test
  # ==========================================================================
  # prompt_order format handling
  # ==========================================================================

  def test_flat_prompt_order_format
    # Flat format: [{identifier, enabled}, ...]
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "Main prompt", "role" => "system" },
        { "identifier" => "jailbreak", "content" => "PHI prompt", "role" => "system" },
        { "identifier" => "chatHistory", "marker" => true },
      ],
      "prompt_order" => [
        { "identifier" => "main", "enabled" => true },
        { "identifier" => "chatHistory", "enabled" => true },
        { "identifier" => "jailbreak", "enabled" => false },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    assert_equal 3, entries.size

    # Order should follow prompt_order
    assert_equal "main_prompt", entries[0].id
    assert entries[0].enabled?

    assert_equal "chat_history", entries[1].id
    assert entries[1].enabled?

    assert_equal "post_history_instructions", entries[2].id
    refute entries[2].enabled?
  end

  def test_nested_prompt_order_format_with_global_bucket
    # Nested format: [{character_id: 100000, order: [...]}, ...]
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "Main prompt" },
        { "identifier" => "jailbreak", "content" => "PHI" },
      ],
      "prompt_order" => [
        {
          "character_id" => 100_000,
          "order" => [
            { "identifier" => "jailbreak", "enabled" => true },
            { "identifier" => "main", "enabled" => true },
          ],
        },
        {
          "character_id" => 100_001,
          "order" => [
            { "identifier" => "main", "enabled" => true },
            { "identifier" => "jailbreak", "enabled" => false },
          ],
        },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    # Should use character_id=100000 (global bucket)
    assert_equal 2, entries.size
    assert_equal "post_history_instructions", entries[0].id
    assert_equal "main_prompt", entries[1].id
  end

  def test_nested_prompt_order_format_falls_back_to_first_bucket
    # If no character_id=100000, use first bucket
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "Main prompt" },
        { "identifier" => "jailbreak", "content" => "PHI" },
      ],
      "prompt_order" => [
        {
          "character_id" => 99_999,
          "order" => [
            { "identifier" => "main", "enabled" => false },
            { "identifier" => "jailbreak", "enabled" => true },
          ],
        },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    assert_equal 2, entries.size
    refute entries[0].enabled? # main should be disabled
    assert entries[1].enabled? # jailbreak should be enabled
  end

  def test_empty_prompt_order_uses_prompts_array_order
    json = {
      "prompts" => [
        { "identifier" => "jailbreak", "content" => "PHI" },
        { "identifier" => "main", "content" => "Main prompt" },
      ],
      "prompt_order" => [],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    # Should fall back to prompts array order
    assert_equal 2, entries.size
    assert_equal "post_history_instructions", entries[0].id
    assert_equal "main_prompt", entries[1].id
  end

  def test_missing_prompt_order_uses_prompts_array_order
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "Main prompt" },
        { "identifier" => "jailbreak", "content" => "PHI" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    assert_equal 2, entries.size
    assert_equal "main_prompt", entries[0].id
    assert_equal "post_history_instructions", entries[1].id
  end

  # ==========================================================================
  # Prompt entry properties
  # ==========================================================================

  def test_marker_prompts_are_treated_as_pinned
    json = {
      "prompts" => [
        { "identifier" => "chatHistory", "marker" => true, "name" => "Chat History" },
        { "identifier" => "worldInfoBefore", "marker" => true },
        { "identifier" => "dialogueExamples", "marker" => true },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    entries.each do |entry|
      assert entry.pinned?, "Expected #{entry.id} to be pinned"
    end
  end

  def test_custom_prompts_with_content_are_not_pinned
    json = {
      "prompts" => [
        {
          "identifier" => "my_custom_prompt",
          "name" => "My Custom Prompt",
          "content" => "Custom content here",
          "system_prompt" => true,
          "role" => "system",
        },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    assert_equal 1, entries.size
    refute entries[0].pinned?
    assert_equal "my_custom_prompt", entries[0].id
    assert_equal "Custom content here", entries[0].content
  end

  def test_injection_position_and_depth
    json = {
      "prompts" => [
        {
          "identifier" => "in_chat_prompt",
          "content" => "In-chat content",
          "injection_position" => 1, # 1 = in_chat
          "injection_depth" => 2,
          "injection_order" => 50,
        },
        {
          "identifier" => "relative_prompt",
          "content" => "Relative content",
          "injection_position" => 0, # 0 = relative
        },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    in_chat = entries.find { |e| e.id == "in_chat_prompt" }
    relative = entries.find { |e| e.id == "relative_prompt" }

    assert in_chat.in_chat?
    assert_equal 2, in_chat.depth
    assert_equal 50, in_chat.order

    assert relative.relative?
  end

  def test_role_coercion
    json = {
      "prompts" => [
        { "identifier" => "p1", "role" => "system" },
        { "identifier" => "p2", "role" => "user" },
        { "identifier" => "p3", "role" => "assistant" },
        { "identifier" => "p4", "role" => 0 }, # numeric system
        { "identifier" => "p5", "role" => 1 }, # numeric user
        { "identifier" => "p6", "role" => 2 }, # numeric assistant
        { "identifier" => "p7" }, # missing role defaults to system
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries_by_id = preset.prompt_entries.to_h { |e| [e.id, e] }

    assert_equal :system, entries_by_id["p1"].role
    assert_equal :user, entries_by_id["p2"].role
    assert_equal :assistant, entries_by_id["p3"].role
    assert_equal :system, entries_by_id["p4"].role
    assert_equal :user, entries_by_id["p5"].role
    assert_equal :assistant, entries_by_id["p6"].role
    assert_equal :system, entries_by_id["p7"].role
  end

  def test_injection_trigger_parsing_with_strings
    # ST uses string values for injection_trigger
    json = {
      "prompts" => [
        {
          "identifier" => "normal_only",
          "content" => "Normal generation only",
          "injection_trigger" => ["normal"],
        },
        {
          "identifier" => "impersonate_only",
          "content" => "Impersonate only",
          "injection_trigger" => ["impersonate"],
        },
        {
          "identifier" => "multiple_triggers",
          "content" => "Multiple",
          "injection_trigger" => ["normal", "continue", "swipe"],
        },
        {
          "identifier" => "no_trigger",
          "content" => "All types",
          # No injection_trigger = all types
        },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries_by_id = preset.prompt_entries.to_h { |e| [e.id, e] }

    assert_equal [:normal], entries_by_id["normal_only"].triggers
    assert_equal [:impersonate], entries_by_id["impersonate_only"].triggers
    assert_equal [:continue, :normal, :swipe], entries_by_id["multiple_triggers"].triggers.sort
    assert_empty entries_by_id["no_trigger"].triggers # empty = all types
  end

  def test_injection_trigger_parsing_with_numeric_codes
    # Also support numeric codes (as per TRIGGER_CODE_MAP)
    json = {
      "prompts" => [
        {
          "identifier" => "normal_only",
          "content" => "Normal generation only",
          "injection_trigger" => [0], # 0 = normal
        },
        {
          "identifier" => "impersonate_only",
          "content" => "Impersonate only",
          "injection_trigger" => [2], # 2 = impersonate
        },
        {
          "identifier" => "swipe_only",
          "content" => "Swipe only",
          "injection_trigger" => [3], # 3 = swipe
        },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries_by_id = preset.prompt_entries.to_h { |e| [e.id, e] }

    assert_equal [:normal], entries_by_id["normal_only"].triggers
    assert_equal [:impersonate], entries_by_id["impersonate_only"].triggers
    assert_equal [:swipe], entries_by_id["swipe_only"].triggers
  end

  def test_forbid_overrides_flag
    json = {
      "prompts" => [
        { "identifier" => "locked", "content" => "Locked", "forbid_overrides" => true },
        { "identifier" => "unlocked", "content" => "Unlocked", "forbid_overrides" => false },
        { "identifier" => "default", "content" => "Default" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries_by_id = preset.prompt_entries.to_h { |e| [e.id, e] }

    assert entries_by_id["locked"].forbid_overrides
    refute entries_by_id["unlocked"].forbid_overrides
    refute entries_by_id["default"].forbid_overrides
  end

  # ==========================================================================
  # ST identifier mapping
  # ==========================================================================

  def test_st_identifier_to_tavernkit_id_mapping
    json = {
      "prompts" => [
        { "identifier" => "main" },
        { "identifier" => "worldInfoBefore", "marker" => true },
        { "identifier" => "personaDescription", "marker" => true },
        { "identifier" => "charDescription", "marker" => true },
        { "identifier" => "charPersonality", "marker" => true },
        { "identifier" => "scenario", "marker" => true },
        { "identifier" => "worldInfoAfter", "marker" => true },
        { "identifier" => "dialogueExamples", "marker" => true },
        { "identifier" => "enhanceDefinitions" },
        { "identifier" => "chatHistory", "marker" => true },
        { "identifier" => "jailbreak" },
        { "identifier" => "nsfw" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    ids = preset.prompt_entries.map(&:id)

    expected_ids = %w[
      main_prompt
      world_info_before_char_defs
      persona_description
      character_description
      character_personality
      scenario
      world_info_after_char_defs
      chat_examples
      enhance_definitions
      chat_history
      post_history_instructions
      auxiliary_prompt
    ]

    assert_equal expected_ids, ids
  end

  def test_alternative_identifier_aliases
    # Test that alternative/snake_case identifiers are also mapped correctly
    json = {
      "prompts" => [
        { "identifier" => "mainPrompt" },
        { "identifier" => "postHistoryInstructions" },
        { "identifier" => "persona_description", "marker" => true },
        { "identifier" => "character_description", "marker" => true },
        { "identifier" => "auxiliaryPrompt" },
        { "identifier" => "dialogue_examples", "marker" => true },
        { "identifier" => "chat_history", "marker" => true },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    ids = preset.prompt_entries.map(&:id)

    assert_includes ids, "main_prompt"
    assert_includes ids, "post_history_instructions"
    assert_includes ids, "persona_description"
    assert_includes ids, "character_description"
    assert_includes ids, "auxiliary_prompt"
    assert_includes ids, "chat_examples"
    assert_includes ids, "chat_history"
  end

  def test_world_info_extended_positions
    json = {
      "prompts" => [
        { "identifier" => "worldInfoBeforeExamples", "marker" => true },
        { "identifier" => "worldInfoAfterExamples", "marker" => true },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    ids = preset.prompt_entries.map(&:id)

    assert_includes ids, "world_info_before_example_messages"
    assert_includes ids, "world_info_after_example_messages"
  end

  def test_authors_note_identifier
    json = {
      "prompts" => [
        { "identifier" => "authorsNote", "marker" => true },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    ids = preset.prompt_entries.map(&:id)

    assert_includes ids, "authors_note"
  end

  # ==========================================================================
  # Content extraction
  # ==========================================================================

  def test_main_prompt_extraction_from_prompts_array
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "Custom main prompt from prompts array" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal "Custom main prompt from prompts array", preset.main_prompt
  end

  def test_main_prompt_defaults_when_empty
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal TavernKit::Preset::DEFAULT_MAIN_PROMPT, preset.main_prompt
  end

  def test_phi_extraction_from_prompts_array
    json = {
      "prompts" => [
        { "identifier" => "jailbreak", "content" => "Custom PHI" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal "Custom PHI", preset.post_history_instructions
  end

  def test_auxiliary_prompt_extraction
    json = {
      "prompts" => [
        { "identifier" => "nsfw", "content" => "NSFW prompt content" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal "NSFW prompt content", preset.auxiliary_prompt
  end

  def test_enhance_definitions_extraction
    json = {
      "prompts" => [
        { "identifier" => "enhanceDefinitions", "content" => "Custom enhance definitions" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal "Custom enhance definitions", preset.enhance_definitions
  end

  # ==========================================================================
  # Top-level settings
  # ==========================================================================

  def test_context_and_token_settings
    json = {
      "openai_max_context" => 8192,
      "openai_max_tokens" => 500,
      "message_token_overhead" => 6,
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal 8192, preset.context_window_tokens
    assert_equal 500, preset.reserved_response_tokens
    assert_equal 6, preset.message_token_overhead
  end

  def test_world_info_settings
    json = {
      "world_info_depth" => 10,
      "world_info_budget" => 2048,
      "world_info_budget_cap" => 50,
      "world_info_include_names" => false,
      "world_info_min_activations" => 2,
      "world_info_min_activations_depth_max" => 5,
      "world_info_use_group_scoring" => true,
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal 10, preset.world_info_depth
    assert_equal 2048, preset.world_info_budget
    assert_equal 50, preset.world_info_budget_cap
    refute preset.world_info_include_names
    assert_equal 2, preset.world_info_min_activations
    assert_equal 5, preset.world_info_min_activations_depth_max
    assert preset.world_info_use_group_scoring
  end

  def test_prompt_text_settings
    json = {
      "new_chat_prompt" => "[NEW CHAT]",
      "new_group_chat_prompt" => "[NEW GROUP]",
      "group_nudge_prompt" => "[NUDGE]",
      "continue_nudge_prompt" => "[CONTINUE]",
      "new_example_chat_prompt" => "[EXAMPLE]",
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal "[NEW CHAT]", preset.new_chat_prompt
    assert_equal "[NEW GROUP]", preset.new_group_chat_prompt
    assert_equal "[NUDGE]", preset.group_nudge_prompt
    assert_equal "[CONTINUE]", preset.continue_nudge_prompt
    assert_equal "[EXAMPLE]", preset.new_example_chat
  end

  def test_format_settings
    json = {
      "wi_format" => "[WI: {0}]",
      "scenario_format" => "Scenario: {{scenario}}",
      "personality_format" => "Personality: {{personality}}",
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal "[WI: {0}]", preset.wi_format
    assert_equal "Scenario: {{scenario}}", preset.scenario_format
    assert_equal "Personality: {{personality}}", preset.personality_format
  end

  def test_boolean_settings
    json = {
      "squash_system_messages" => true,
      "continue_prefill" => true,
      "prefer_character_prompt" => false,
      "prefer_character_jailbreak" => false,
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert preset.squash_system_messages
    assert preset.continue_prefill
    refute preset.prefer_char_prompt
    refute preset.prefer_char_instructions
  end

  def test_continue_postfix_numeric_codes
    # ST uses numeric codes: 0="", 1=" ", 2="\n", 3="\n\n"
    [
      [0, ""],
      [1, " "],
      [2, "\n"],
      [3, "\n\n"],
      ["1", " "],  # String numeric
    ].each do |input, expected|
      json = { "continue_postfix" => input }
      preset = TavernKit::Preset::StImporter.new(json).to_preset
      assert_equal expected, preset.continue_postfix, "Failed for input: #{input.inspect}"
    end
  end

  def test_continue_postfix_string_value
    json = { "continue_postfix" => "..." }
    preset = TavernKit::Preset::StImporter.new(json).to_preset
    assert_equal "...", preset.continue_postfix
  end

  def test_authors_note_settings
    json = {
      "authors_note" => "Remember: this is important",
      "authors_note_frequency" => 3,
      "authors_note_position" => 1, # 1 = in_chat
      "authors_note_depth" => 2,
      "authors_note_role" => 1, # 1 = user
      "allowWIScan" => true,
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_equal "Remember: this is important", preset.authors_note
    assert_equal 3, preset.authors_note_frequency
    assert_equal :in_chat, preset.authors_note_position
    assert_equal 2, preset.authors_note_depth
    assert_equal :user, preset.authors_note_role
    assert preset.authors_note_allow_wi_scan
  end

  # ==========================================================================
  # Instruct and Context Template integration
  # ==========================================================================

  def test_instruct_settings_extraction
    json = {
      "instruct" => {
        "enabled" => true,
        "input_sequence" => "<|im_start|>user",
        "output_sequence" => "<|im_start|>assistant",
        "system_sequence" => "<|im_start|>system",
        "input_suffix" => "<|im_end|>",
        "output_suffix" => "<|im_end|>",
        "system_suffix" => "<|im_end|>",
        "stop_sequence" => "<|im_end|>",
        "wrap" => true,
        "names_behavior" => "force",
      },
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_instance_of TavernKit::Instruct, preset.instruct
    assert preset.instruct.enabled
    assert_equal "<|im_start|>user", preset.instruct.input_sequence
    assert_equal "<|im_start|>assistant", preset.instruct.output_sequence
    assert_equal "<|im_start|>system", preset.instruct.system_sequence
    assert_equal "<|im_end|>", preset.instruct.stop_sequence
  end

  def test_context_template_extraction
    json = {
      "context" => {
        "story_string" => "{{description}}\n{{personality}}",
        "chat_start" => "---",
        "example_separator" => "***",
        "use_stop_strings" => false,
        "names_as_stop_strings" => true,
      },
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_instance_of TavernKit::ContextTemplate, preset.context_template
    assert_equal "{{description}}\n{{personality}}", preset.context_template.story_string
    assert_equal "---", preset.context_template.chat_start
    assert_equal "***", preset.context_template.example_separator
    refute preset.context_template.use_stop_strings
    assert preset.context_template.names_as_stop_strings
  end

  def test_missing_instruct_returns_nil
    json = { "prompts" => [] }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_nil preset.instruct
  end

  def test_missing_context_returns_nil
    json = { "prompts" => [] }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_nil preset.context_template
  end

  # ==========================================================================
  # Edge cases and robustness
  # ==========================================================================

  def test_empty_json_produces_valid_preset
    json = {}

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_instance_of TavernKit::Preset, preset
    assert_equal TavernKit::Preset::DEFAULT_MAIN_PROMPT, preset.main_prompt
  end

  def test_handles_nil_values_gracefully
    json = {
      "prompts" => nil,
      "prompt_order" => nil,
      "openai_max_context" => nil,
      "instruct" => nil,
      "context" => nil,
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    assert_instance_of TavernKit::Preset, preset
    assert_nil preset.context_window_tokens
    assert_nil preset.instruct
    assert_nil preset.context_template
  end

  def test_handles_prompts_with_missing_identifier
    json = {
      "prompts" => [
        { "content" => "No identifier" },
        { "identifier" => "main", "content" => "Has identifier" },
        { "identifier" => nil, "content" => "Nil identifier" },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    # Should only have the one with valid identifier
    assert_equal 1, entries.size
    assert_equal "main_prompt", entries[0].id
  end

  def test_prompts_not_in_prompt_order_are_not_included
    # If prompt_order is provided, only prompts in prompt_order should be included
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "Main" },
        { "identifier" => "extra", "content" => "Extra" },
        { "identifier" => "jailbreak", "content" => "PHI" },
      ],
      "prompt_order" => [
        { "identifier" => "main", "enabled" => true },
        { "identifier" => "jailbreak", "enabled" => true },
        # "extra" not in prompt_order
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    # Only main and jailbreak should be included
    assert_equal 2, entries.size
    ids = entries.map(&:id)
    assert_includes ids, "main_prompt"
    assert_includes ids, "post_history_instructions"
    refute_includes ids, "extra"
  end

  def test_prompt_order_references_missing_prompt
    # prompt_order references an identifier not in prompts array
    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "Main" },
      ],
      "prompt_order" => [
        { "identifier" => "main", "enabled" => true },
        { "identifier" => "nonexistent", "enabled" => true },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset
    entries = preset.prompt_entries

    # Should handle gracefully - nonexistent still gets an entry but empty
    assert_equal 2, entries.size
  end

  def test_load_file_class_method
    # Create a temp file
    require "tempfile"

    json = {
      "prompts" => [
        { "identifier" => "main", "content" => "File test" },
      ],
    }

    Tempfile.create(["preset", ".json"]) do |f|
      f.write(JSON.generate(json))
      f.flush

      preset = TavernKit::Preset::StImporter.load_file(f.path)

      assert_instance_of TavernKit::Preset, preset
      assert_equal "File test", preset.main_prompt
    end
  end

  # ==========================================================================
  # Full ST preset compatibility
  # ==========================================================================

  def test_full_st_openai_preset_structure
    # Simulates a complete ST OpenAI preset structure
    json = {
      "chat_completion_source" => "openai",
      "openai_model" => "gpt-4-turbo",
      "temperature" => 1,
      "frequency_penalty" => 0,
      "presence_penalty" => 0,
      "top_p" => 1,
      "openai_max_context" => 4095,
      "openai_max_tokens" => 300,
      "send_if_empty" => "",
      "new_chat_prompt" => "[Start a new Chat]",
      "new_group_chat_prompt" => "[Start a new group chat. Group members: {{group}}]",
      "continue_nudge_prompt" => "[Continue your last message]",
      "group_nudge_prompt" => "[Write the next reply only as {{char}}.]",
      "wi_format" => "{0}",
      "scenario_format" => "{{scenario}}",
      "personality_format" => "{{personality}}",
      "prompts" => [
        { "name" => "Main Prompt", "identifier" => "main", "role" => "system",
          "content" => "Write {{char}}'s next reply in a fictional chat." },
        { "name" => "Auxiliary Prompt", "identifier" => "nsfw", "role" => "system", "content" => "" },
        { "identifier" => "dialogueExamples", "name" => "Chat Examples", "marker" => true },
        { "name" => "Post-History Instructions", "identifier" => "jailbreak", "role" => "system", "content" => "" },
        { "identifier" => "chatHistory", "name" => "Chat History", "marker" => true },
        { "identifier" => "worldInfoAfter", "name" => "World Info (after)", "marker" => true },
        { "identifier" => "worldInfoBefore", "name" => "World Info (before)", "marker" => true },
        { "identifier" => "enhanceDefinitions", "role" => "system",
          "content" => "If you have more knowledge of {{char}}, add to the character's lore." },
        { "identifier" => "charDescription", "name" => "Char Description", "marker" => true },
        { "identifier" => "charPersonality", "name" => "Char Personality", "marker" => true },
        { "identifier" => "scenario", "name" => "Scenario", "marker" => true },
        { "identifier" => "personaDescription", "name" => "Persona Description", "marker" => true },
      ],
      "prompt_order" => [
        {
          "character_id" => 100_000,
          "order" => [
            { "identifier" => "main", "enabled" => true },
            { "identifier" => "worldInfoBefore", "enabled" => true },
            { "identifier" => "charDescription", "enabled" => true },
            { "identifier" => "charPersonality", "enabled" => true },
            { "identifier" => "scenario", "enabled" => true },
            { "identifier" => "enhanceDefinitions", "enabled" => false },
            { "identifier" => "nsfw", "enabled" => true },
            { "identifier" => "worldInfoAfter", "enabled" => true },
            { "identifier" => "dialogueExamples", "enabled" => true },
            { "identifier" => "chatHistory", "enabled" => true },
            { "identifier" => "jailbreak", "enabled" => true },
          ],
        },
      ],
    }

    preset = TavernKit::Preset::StImporter.new(json).to_preset

    # Verify core properties
    assert_equal "Write {{char}}'s next reply in a fictional chat.", preset.main_prompt
    assert_equal 4095, preset.context_window_tokens
    assert_equal 300, preset.reserved_response_tokens

    # Verify prompt order
    entries = preset.prompt_entries
    assert_equal 11, entries.size

    # Check order matches prompt_order
    expected_order = %w[
      main_prompt
      world_info_before_char_defs
      character_description
      character_personality
      scenario
      enhance_definitions
      auxiliary_prompt
      world_info_after_char_defs
      chat_examples
      chat_history
      post_history_instructions
    ]
    assert_equal expected_order, entries.map(&:id)

    # enhanceDefinitions should be disabled
    enhance = entries.find { |e| e.id == "enhance_definitions" }
    refute enhance.enabled?
  end
end
