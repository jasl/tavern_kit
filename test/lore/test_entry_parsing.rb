# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Lore
    class TestEntryParsing < Minitest::Test
      def test_parses_st_numeric_fields
        entry = Entry.from_hash(
          {
            "uid" => 123,
            "key" => ["key"],
            "keysecondary" => ["a", "b"],
            "selective" => true,
            "selectiveLogic" => 3, # AND ALL
            "position" => 5, # top of example messages
            "order" => 42,
            "disable" => true,
          },
          source: :global,
          book_name: "Global Lore"
        )

        assert_equal 123, entry.uid
        assert_equal ["key"], entry.keys
        assert_equal ["a", "b"], entry.secondary_keys
        assert_equal true, entry.selective
        assert_equal :and_all, entry.selective_logic
        assert_equal :before_example_messages, entry.position
        assert_equal 42, entry.insertion_order
        assert_equal false, entry.enabled
        assert_equal :global, entry.source
        assert_equal "Global Lore", entry.book_name
      end

      def test_parses_disable_inverse_of_enabled
        e1 = Entry.from_hash({ "uid" => 1, "key" => ["x"], "enabled" => false })
        e2 = Entry.from_hash({ "uid" => 2, "key" => ["x"], "disable" => true })

        assert_equal false, e1.enabled
        assert_equal false, e2.enabled
      end
    end
  end
end
