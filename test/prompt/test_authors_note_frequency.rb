# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    # Tests for Author's Note frequency feature.
    #
    # The frequency setting controls how often Author's Note is inserted:
    # SillyTavern semantics (https://docs.sillytavern.app/usage/core-concepts/authors-note/):
    # - 0: Author's Note will NEVER be inserted
    # - 1: Author's Note will be inserted with every user input prompt (default)
    # - N > 1: Insert only when user message count is divisible by N
    #
    # User message count = (user messages in history) + 1 (current message)
    #
    # Ref: ROADMAP.md - "Frequency: Insert every N user messages"
    class TestAuthorsNoteFrequency < Minitest::Test
      def setup
        @character = build_simple_card
        @user = User.new(name: "Bob", persona: nil)
      end

      def build_simple_card
        CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A helpful assistant",
              "personality" => "",
              "scenario" => "",
              "system_prompt" => nil,
              "post_history_instructions" => nil,
              "first_mes" => "",
              "mes_example" => "",
            },
          }
        )
      end

      def build_preset(frequency:, authors_note: "AUTHOR_NOTE_CONTENT")
        Preset.new(
          main_prompt: "MAIN",
          post_history_instructions: "",
          authors_note: authors_note,
          authors_note_frequency: frequency,
        )
      end

      def build_history(user_message_count)
        messages = []
        user_message_count.times do |i|
          messages << Message.new(role: :user, content: "User message #{i + 1}")
          messages << Message.new(role: :assistant, content: "Response #{i + 1}")
        end
        ChatHistory.wrap(messages)
      end

      def author_note_present?(plan)
        plan.blocks.any? { |b| b.slot == :authors_note }
      end

      # ============================================
      # Default behavior (frequency = 1)
      # ============================================

      def test_default_frequency_is_one
        preset = Preset.new(authors_note: "AN")
        assert_equal 1, preset.authors_note_frequency
      end

      def test_frequency_one_always_inserts_author_note
        preset = build_preset(frequency: 1)

        # First message (user count = 1)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        assert author_note_present?(plan), "AN should be present on first message"

        # Second message (user count = 2)
        history = build_history(1) # 1 user message in history
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Hello again")
        assert author_note_present?(plan), "AN should be present on second message"

        # Third message (user count = 3)
        history = build_history(2)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Third")
        assert author_note_present?(plan), "AN should be present on third message"
      end

      def test_frequency_zero_means_never_insert
        preset = build_preset(frequency: 0)

        # ST behavior: frequency=0 means "never insert"
        assert_equal 0, preset.authors_note_frequency

        # First message - AN should NOT be present
        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        refute author_note_present?(plan), "frequency=0 should NEVER insert AN (per ST docs)"

        # Second message - AN should still NOT be present
        history = build_history(1)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Hello again")
        refute author_note_present?(plan), "frequency=0 should NEVER insert AN (per ST docs)"

        # Many messages later - AN should still NOT be present
        history = build_history(99)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Message 100")
        refute author_note_present?(plan), "frequency=0 should NEVER insert AN regardless of message count"
      end

      # ============================================
      # Frequency = 2 (every other message)
      # ============================================

      def test_frequency_two_inserts_on_even_numbered_messages
        preset = build_preset(frequency: 2)

        # User message count = 1 (1 % 2 = 1, not zero) -> no AN
        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "First")
        refute author_note_present?(plan), "AN should NOT be present on message #1"

        # User message count = 2 (2 % 2 = 0) -> insert AN
        history = build_history(1)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Second")
        assert author_note_present?(plan), "AN should be present on message #2"

        # User message count = 3 (3 % 2 = 1) -> no AN
        history = build_history(2)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Third")
        refute author_note_present?(plan), "AN should NOT be present on message #3"

        # User message count = 4 (4 % 2 = 0) -> insert AN
        history = build_history(3)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Fourth")
        assert author_note_present?(plan), "AN should be present on message #4"
      end

      # ============================================
      # Frequency = 3 (every third message)
      # ============================================

      def test_frequency_three_inserts_every_third_message
        preset = build_preset(frequency: 3)

        # Message 1: 1 % 3 = 1 -> no AN
        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "One")
        refute author_note_present?(plan), "AN should NOT be present on message #1"

        # Message 2: 2 % 3 = 2 -> no AN
        history = build_history(1)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Two")
        refute author_note_present?(plan), "AN should NOT be present on message #2"

        # Message 3: 3 % 3 = 0 -> insert AN
        history = build_history(2)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Three")
        assert author_note_present?(plan), "AN should be present on message #3"

        # Message 4: 4 % 3 = 1 -> no AN
        history = build_history(3)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Four")
        refute author_note_present?(plan), "AN should NOT be present on message #4"

        # Message 5: 5 % 3 = 2 -> no AN
        history = build_history(4)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Five")
        refute author_note_present?(plan), "AN should NOT be present on message #5"

        # Message 6: 6 % 3 = 0 -> insert AN
        history = build_history(5)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Six")
        assert author_note_present?(plan), "AN should be present on message #6"
      end

      # ============================================
      # Edge cases
      # ============================================

      def test_negative_frequency_treated_as_zero_never_insert
        preset = build_preset(frequency: -1)

        # ST behavior: negative values treated as 0 (never insert)
        assert_equal 0, preset.authors_note_frequency

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        refute author_note_present?(plan), "negative frequency should be treated as 0 (never insert)"
      end

      def test_large_frequency_value
        preset = build_preset(frequency: 100)

        # Messages 1-99 should not have AN
        (1..99).each do |n|
          history = build_history(n - 1)
          plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Message #{n}")
          refute author_note_present?(plan), "AN should NOT be present on message ##{n}"
        end

        # Message 100 should have AN
        history = build_history(99)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Message 100")
        assert author_note_present?(plan), "AN should be present on message #100"
      end

      def test_empty_authors_note_never_inserted_regardless_of_frequency
        preset = build_preset(frequency: 2, authors_note: "")

        # Even on message #2 where frequency=2 would normally insert, empty AN is skipped
        history = build_history(1)
        plan = TavernKit.build(character: @character, user: @user, preset: preset, history: history, message: "Second")
        refute author_note_present?(plan), "Empty AN should never be inserted"
      end

      def test_whitespace_only_authors_note_not_inserted
        preset = build_preset(frequency: 1, authors_note: "   \n\t  ")

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")
        refute author_note_present?(plan), "Whitespace-only AN should not be inserted"
      end

      # ============================================
      # Integration with World Info top/bottom AN
      # ============================================

      def test_frequency_affects_world_info_an_positions
        # When AN is skipped due to frequency, top_of_an and bottom_of_an
        # World Info entries should also not appear.
        card = CharacterCard.load(
          {
            "spec" => "chara_card_v2",
            "spec_version" => "2.0",
            "data" => {
              "name" => "Alice",
              "description" => "A helpful assistant",
              "character_book" => {
                "scan_depth" => 10,
                "token_budget" => 1000,
                "entries" => [
                  {
                    "uid" => "top",
                    "keys" => ["hello"],
                    "content" => "TOP_AN_WI",
                    "position" => "top_of_an",
                  },
                  {
                    "uid" => "bottom",
                    "keys" => ["hello"],
                    "content" => "BOTTOM_AN_WI",
                    "position" => "bottom_of_an",
                  },
                ],
              },
            },
          }
        )

        preset = build_preset(frequency: 2, authors_note: "AN_CONTENT")

        # Message #1: frequency=2 means no AN (1 % 2 = 1)
        plan = TavernKit.build(character: card, user: @user, preset: preset, message: "hello")
        blocks = plan.blocks

        refute blocks.any? { |b| b.slot == :authors_note },
               "AN should not be present on message #1"
        refute blocks.any? { |b| b.content.include?("TOP_AN_WI") },
               "top_of_an WI content should not be present when AN is skipped"
        refute blocks.any? { |b| b.content.include?("BOTTOM_AN_WI") },
               "bottom_of_an WI content should not be present when AN is skipped"

        # Message #2: frequency=2 means insert AN (2 % 2 = 0)
        history = build_history(1)
        plan = TavernKit.build(character: card, user: @user, preset: preset, history: history, message: "hello")
        blocks = plan.blocks

        an_block = blocks.find { |b| b.slot == :authors_note }
        refute_nil an_block, "AN should be present on message #2"

        top_idx = an_block.content.index("TOP_AN_WI")
        an_idx = an_block.content.index("AN_CONTENT")
        bottom_idx = an_block.content.index("BOTTOM_AN_WI")

        refute_nil top_idx, "top_of_an WI content should be present when AN is inserted"
        refute_nil an_idx, "AN content should be present when AN is inserted"
        refute_nil bottom_idx, "bottom_of_an WI content should be present when AN is inserted"

        assert top_idx < an_idx, "TOP_AN_WI should come before AN_CONTENT"
        assert an_idx < bottom_idx, "BOTTOM_AN_WI should come after AN_CONTENT"
      end

      # ============================================
      # ST Preset Loading
      # ============================================

      def test_st_preset_json_loads_frequency
        hash = {
          "authors_note" => "AN_CONTENT",
          "authors_note_frequency" => 5,
        }

        preset = Preset.from_st_preset_json(hash)

        assert_equal 5, preset.authors_note_frequency
        assert_equal "AN_CONTENT", preset.authors_note
      end

      def test_st_preset_json_defaults_frequency_to_one
        hash = {
          "authors_note" => "AN_CONTENT",
          # no frequency specified
        }

        preset = Preset.from_st_preset_json(hash)

        assert_equal 1, preset.authors_note_frequency
      end

      # ============================================
      # Verify content is correct when inserted
      # ============================================

      def test_authors_note_content_is_correct_when_inserted
        preset = build_preset(frequency: 1, authors_note: "This is the author's note for {{char}}")

        plan = TavernKit.build(character: @character, user: @user, preset: preset, message: "Hello")

        an_block = plan.blocks.find { |b| b.slot == :authors_note }
        refute_nil an_block
        assert_equal "This is the author's note for Alice", an_block.content
      end
    end
  end
end
