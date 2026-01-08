# frozen_string_literal: true

require "test_helper"

module TavernKit
  module STCompatibility
    class TestUtilityPrompts < Minitest::Test
      def setup
        @user = User.new(name: "Bob", persona: nil)
      end

      def test_format_templates_apply_to_scenario_personality_and_wi
        character = Character.create(
          name: "Alice",
          description: "Desc",
          personality: "Brave {{user}}",
          scenario: "Meet {{char}}",
          mes_example: "",
          character_book: {
            "scan_depth" => 10,
            "entries" => [
              { "uid" => "wi1", "keys" => ["magic"], "content" => "Lore {{char}}", "position" => "before_char_defs" },
            ],
          },
        )

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          wi_format: "WI::{0}",
          scenario_format: "Scenario: {{scenario}}",
          personality_format: "Personality: {{personality}}",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, message: "magic")

        scenario_block = plan.blocks.find { |b| b.slot == :scenario }
        personality_block = plan.blocks.find { |b| b.slot == :character_personality }
        wi_block = plan.blocks.find { |b| b.slot == :world_info_before_char_defs }

        refute_nil scenario_block
        refute_nil personality_block
        refute_nil wi_block

        assert_includes scenario_block.content, "Scenario: Meet Alice"
        assert_includes personality_block.content, "Personality: Brave Bob"
        assert_includes wi_block.content, "WI::Lore Alice"
      end

      def test_new_chat_prompt_and_replace_empty_message
        character = Character.create(name: "Alice", mes_example: "")
        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "Hi"),
          Prompt::Message.new(role: :assistant, content: "Hello"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          new_chat_prompt: "NEW CHAT",
          replace_empty_message: "EMPTY",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, history: history, message: "")
        contents = plan.to_messages.map { |m| m[:content] }

        new_idx = contents.index("NEW CHAT")
        hi_idx = contents.index("Hi")
        hello_idx = contents.index("Hello")
        empty_idx = contents.index("EMPTY")

        refute_nil new_idx
        refute_nil hi_idx
        refute_nil hello_idx
        refute_nil empty_idx

        assert new_idx < hi_idx, "new_chat_prompt should precede chat history"
        assert empty_idx > hello_idx, "replace_empty_message should appear after last assistant message"
      end

      def test_replace_empty_message_is_not_appended_when_history_ends_with_user
        character = Character.create(name: "Alice", mes_example: "")
        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "Hi"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          replace_empty_message: "EMPTY",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, history: history)
        messages = plan.to_messages

        refute messages.any? { |m| m[:role] == "user" && m[:content].to_s.strip.empty? }, "should not append empty user message"
        refute messages.any? { |m| m[:content] == "EMPTY" }, "should not insert replace_empty_message when last history is user"
      end

      def test_replace_empty_message_is_appended_when_history_ends_with_assistant_and_no_message
        character = Character.create(name: "Alice", mes_example: "")
        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "Hi"),
          Prompt::Message.new(role: :assistant, content: "Hello"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          replace_empty_message: "EMPTY",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, history: history)
        contents = plan.to_messages.map { |m| m[:content] }

        hello_idx = contents.index("Hello")
        empty_idx = contents.index("EMPTY")

        refute_nil hello_idx
        refute_nil empty_idx
        assert empty_idx > hello_idx, "replace_empty_message should appear after last assistant message"
      end

      def test_new_group_chat_prompt_is_used_in_group_chat
        character = Character.create(name: "Alice", mes_example: "")
        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "Hi"),
          Prompt::Message.new(role: :assistant, content: "Hello"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          new_chat_prompt: "NEW CHAT",
          new_group_chat_prompt: "NEW GROUP",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        group = TavernKit::GroupContext.from_members(%w[Alice Eve])
        plan = TavernKit.build(character: character, user: @user, preset: preset, group: group, history: history, message: "Hey")
        contents = plan.to_messages.map { |m| m[:content] }

        assert_includes contents, "NEW GROUP"
        refute_includes contents, "NEW CHAT"
      end

      def test_group_nudge_appended_in_group_chat
        character = Character.create(name: "Alice", mes_example: "")

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          group_nudge_prompt: "NUDGE {{char}}",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        group = TavernKit::GroupContext.from_members(%w[Alice Eve])
        plan = TavernKit.build(character: character, user: @user, preset: preset, group: group, message: "Hi")
        contents = plan.to_messages.map { |m| m[:content] }

        hi_idx = contents.index("Hi")
        nudge_idx = contents.index("NUDGE Alice")

        refute_nil hi_idx
        refute_nil nudge_idx
        assert nudge_idx > hi_idx, "group nudge should be appended after the current user message"
      end

      def test_group_nudge_is_skipped_for_impersonate_generation
        character = Character.create(name: "Alice", mes_example: "")

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          group_nudge_prompt: "NUDGE {{char}}",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(
          character: character,
          user: @user,
          preset: preset,
          group: TavernKit::GroupContext.from_members(%w[Alice Eve]),
          generation_type: :impersonate,
          message: "Hi"
        )

        contents = plan.to_messages.map { |m| m[:content] }
        refute_includes contents, "NUDGE Alice"
      end

      def test_impersonation_prompt_is_appended_for_impersonate_generation
        character = Character.create(name: "Alice", mes_example: "")

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "PHI",
          impersonation_prompt: "IMPERSONATE {{user}} NOT {{char}}",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
            { "id" => "post_history_instructions", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, generation_type: :impersonate, message: "Hi")
        messages = plan.to_messages

        assert_equal "system", messages.last[:role]
        assert_equal "IMPERSONATE Bob NOT Alice", messages.last[:content]

        phi_idx = messages.index { |m| m[:content] == "PHI" }
        refute_nil phi_idx
        assert phi_idx < (messages.length - 1), "PHI should appear before impersonation prompt"
      end

      def test_continue_nudge_appended_after_prompt_manager
        character = Character.create(name: "Alice", mes_example: "")
        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "Hi"),
          Prompt::Message.new(role: :assistant, content: "Hello"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          continue_nudge_prompt: "NUDGE {{lastChatMessage}}",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(
          character: character,
          user: @user,
          preset: preset,
          history: history,
          generation_type: :continue,
          message: ""
        )

        contents = plan.to_messages.map { |m| m[:content] }

        hi_idx = contents.index("Hi")
        hello_idx = contents.index("Hello")
        nudge_idx = contents.index("NUDGE Hello")

        refute_nil hi_idx
        refute_nil hello_idx
        refute_nil nudge_idx

        assert hello_idx > hi_idx, "continued message should follow chat history"
        assert nudge_idx > hello_idx, "continue nudge should follow the continued message"
        assert_equal 1, contents.count("Hello")
      end

      def test_continue_prefill_skips_continue_nudge_and_appends_postfix
        character = Character.create(name: "Alice", mes_example: "")
        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "Hi"),
          Prompt::Message.new(role: :assistant, content: "Hello"),
        ])

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          continue_nudge_prompt: "NUDGE {{lastChatMessage}}",
          continue_prefill: true,
          continue_postfix: " ",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        plan = TavernKit.build(
          character: character,
          user: @user,
          preset: preset,
          history: history,
          generation_type: :continue,
          message: ""
        )

        contents = plan.to_messages.map { |m| m[:content] }

        refute_includes contents, "NUDGE Hello", "continue nudge should be skipped when continue_prefill is enabled"

        hi_idx = contents.index("Hi")
        continued_idx = contents.find_index { |c| c.start_with?("Hello") }
        refute_nil hi_idx
        refute_nil continued_idx

        assert continued_idx > hi_idx, "continued message should follow chat history"
        assert contents[continued_idx].end_with?(" "), "continued assistant prefill should apply continue_postfix"
        assert_equal 1, contents.count { |c| c.strip == "Hello" }
      end

      def test_enhance_definitions_and_auxiliary_prompt_from_st_preset
        st_json = {
          "prompts" => [
            { "identifier" => "main", "content" => "MAIN" },
            { "identifier" => "enhanceDefinitions", "content" => "ENHANCE", "system_prompt" => true },
            { "identifier" => "nsfw", "content" => "AUX", "system_prompt" => true },
            { "identifier" => "chatHistory", "marker" => true },
          ],
          "prompt_order" => [
            { "identifier" => "main", "enabled" => true },
            { "identifier" => "enhanceDefinitions", "enabled" => true },
            { "identifier" => "nsfw", "enabled" => true },
            { "identifier" => "chatHistory", "enabled" => true },
          ],
        }

        preset = Preset.from_st_preset_json(st_json)
        character = Character.create(name: "Alice", mes_example: "")

        plan = TavernKit.build(character: character, user: @user, preset: preset, message: "Hello")
        contents = plan.to_messages.map { |m| m[:content] }

        assert_includes contents, "ENHANCE"
        assert_includes contents, "AUX"
      end

      def test_depth_prompt_injection
        character = Character.create(
          name: "Alice",
          mes_example: "",
          extensions: {
            "depth_prompt" => {
              "prompt" => "DEPTH {{char}}",
              "depth" => 1,
              "role" => "assistant",
            },
          },
        )

        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        history = ChatHistory.wrap([
          Prompt::Message.new(role: :user, content: "First"),
          Prompt::Message.new(role: :assistant, content: "Second"),
        ])

        plan = TavernKit.build(character: character, user: @user, preset: preset, history: history, message: "Third")
        messages = plan.to_messages
        contents = messages.map { |m| m[:content] }

        third_idx = contents.index("Third")
        depth_idx = contents.index("DEPTH Alice")

        refute_nil third_idx
        refute_nil depth_idx

        assert depth_idx < third_idx, "depth prompt should be inserted before the last message"
        assert_equal "assistant", messages[depth_idx][:role]
      end

      def test_group_macros_use_members_and_muted_lists
        character = Character.create(name: "Alice", mes_example: "")
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "group_probe",
              "content" => "G={{group}}|GNM={{groupNotMuted}}|CING={{charIfNotGroup}}|NC={{notChar}}",
              "role" => "system",
              "position" => "relative",
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        group_context = TavernKit::GroupContext.new(
          members: ["Alice", "Cara"],
          muted: ["Cara"],
          current_character: "Alice",
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, group: group_context, message: "Hi")
        contents = plan.to_messages.map { |m| m[:content] }
        probe = contents.find { |c| c&.start_with?("G=") }

        refute_nil probe
        assert_equal "G=Alice, Cara|GNM=Alice|CING=Alice, Cara|NC=Cara, Bob", probe
      end

      def test_group_macros_fall_back_to_char_when_group_context_has_no_members
        character = Character.create(name: "Alice", mes_example: "")
        preset = Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          prompt_entries: [
            { "id" => "main_prompt", "pinned" => true },
            {
              "id" => "group_probe",
              "content" => "G={{group}}|GNM={{groupNotMuted}}|CING={{charIfNotGroup}}|NC={{notChar}}",
              "role" => "system",
              "position" => "relative",
            },
            { "id" => "chat_history", "pinned" => true },
          ].map { |h| Prompt::PromptEntry.from_hash(h) },
        )

        group_context = TavernKit::GroupContext.new(
          members: [],
          muted: [],
          current_character: nil,
        )

        plan = TavernKit.build(character: character, user: @user, preset: preset, group: group_context, message: "Hi")
        contents = plan.to_messages.map { |m| m[:content] }
        probe = contents.find { |c| c&.start_with?("G=") }

        refute_nil probe
        assert_equal "G=Alice|GNM=Alice|CING=Alice|NC=Bob", probe
      end
    end
  end
end
