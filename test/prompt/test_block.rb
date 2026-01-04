# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestBlock < Minitest::Test
      def test_minimal_instantiation
        block = Block.new(role: :system, content: "Hello")

        assert_equal :system, block.role
        assert_equal "Hello", block.content
        assert_nil block.name
        assert_nil block.slot
        assert block.enabled?
        assert_equal :relative, block.insertion_point
        assert_equal 0, block.depth
        assert_equal 100, block.order
        assert_equal 100, block.priority
        assert_equal :default, block.token_budget_group
        assert_empty block.tags
        assert_empty block.metadata
        refute_nil block.id # auto-generated UUID
      end

      def test_full_instantiation
        block = Block.new(
          id: "test-block-001",
          role: :user,
          content: "User message",
          slot: :user_message,
          enabled: true,
          insertion_point: :in_chat,
          depth: 2,
          order: 50,
          priority: 10,
          token_budget_group: :history,
          tags: [:important, :current],
          metadata: { custom_key: "custom_value" },
        )

        assert_equal "test-block-001", block.id
        assert_equal :user, block.role
        assert_equal "User message", block.content
        assert_equal :user_message, block.slot
        assert block.enabled?
        assert_equal :in_chat, block.insertion_point
        assert_equal 2, block.depth
        assert_equal 50, block.order
        assert_equal 10, block.priority
        assert_equal :history, block.token_budget_group
        assert_equal [:important, :current], block.tags
        assert_equal({ custom_key: "custom_value" }, block.metadata)
      end

      def test_role_normalization
        assert_equal :system, Block.new(role: :system, content: "").role
        assert_equal :user, Block.new(role: :user, content: "").role
        assert_equal :assistant, Block.new(role: :assistant, content: "").role

        assert_raises(ArgumentError) { Block.new(role: "system", content: "") }
        assert_raises(ArgumentError) { Block.new(role: "SYSTEM", content: "") }
      end

      def test_invalid_role_raises_error
        assert_raises(ArgumentError) do
          Block.new(role: "invalid_role", content: "")
        end

        assert_raises(ArgumentError) do
          Block.new(role: "ai", content: "")
        end
      end

      def test_insertion_point_normalization
        assert_equal :relative, Block.new(role: :system, content: "", insertion_point: :relative).insertion_point
        assert_equal :in_chat, Block.new(role: :system, content: "", insertion_point: :in_chat).insertion_point
        assert_equal :before_char_defs, Block.new(role: :system, content: "", insertion_point: :before_char_defs).insertion_point
        assert_equal :after_char_defs, Block.new(role: :system, content: "", insertion_point: :after_char_defs).insertion_point

        assert_raises(ArgumentError) { Block.new(role: :system, content: "", insertion_point: "in_chat") }
      end

      def test_invalid_insertion_point_raises_error
        assert_raises(ArgumentError) do
          Block.new(role: :system, content: "", insertion_point: :invalid_position)
        end

        assert_raises(ArgumentError) do
          Block.new(role: :system, content: "", insertion_point: :chat)
        end
      end

      def test_budget_group_normalization
        assert_equal :system, Block.new(role: :system, content: "", token_budget_group: :system).token_budget_group
        assert_equal :examples, Block.new(role: :system, content: "", token_budget_group: :examples).token_budget_group
        assert_equal :lore, Block.new(role: :system, content: "", token_budget_group: :lore).token_budget_group
        assert_equal :history, Block.new(role: :system, content: "", token_budget_group: :history).token_budget_group
        assert_equal :custom, Block.new(role: :system, content: "", token_budget_group: :custom).token_budget_group
        assert_equal :default, Block.new(role: :system, content: "", token_budget_group: :default).token_budget_group
        assert_raises(ArgumentError) { Block.new(role: :system, content: "", token_budget_group: :unknown) }
      end

      def test_tags_normalization
        block = Block.new(role: :system, content: "", tags: [:tag1, :tag2, :tag3])
        assert_equal [:tag1, :tag2, :tag3], block.tags
        assert block.tags.frozen?

        assert_raises(ArgumentError) { Block.new(role: :system, content: "", tags: ["tag1"]) }
      end

      def test_enabled_predicate
        enabled_block = Block.new(role: :system, content: "", enabled: true)
        disabled_block = Block.new(role: :system, content: "", enabled: false)

        assert enabled_block.enabled?
        refute enabled_block.disabled?
        refute disabled_block.enabled?
        assert disabled_block.disabled?
      end

      def test_in_chat_and_relative_predicates
        relative_block = Block.new(role: :system, content: "", insertion_point: :relative)
        in_chat_block = Block.new(role: :system, content: "", insertion_point: :in_chat)

        assert relative_block.relative?
        refute relative_block.in_chat?
        assert in_chat_block.in_chat?
        refute in_chat_block.relative?
      end

      def test_to_message
        block = Block.new(role: :user, content: "Hello, world!")
        message = block.to_message

        assert_instance_of Message, message
        assert_equal :user, message.role
        assert_equal "Hello, world!", message.content
        assert_nil message.name
      end

      def test_to_h
        block = Block.new(
          id: "test-id",
          role: :system,
          content: "Test content",
          name: "Narrator",
          slot: :main_prompt,
          enabled: true,
          insertion_point: :relative,
          depth: 0,
          order: 100,
          priority: 50,
          token_budget_group: :system,
          tags: [:core],
          metadata: { key: "value" },
        )

        hash = block.to_h

        assert_equal "test-id", hash[:id]
        assert_equal :system, hash[:role]
        assert_equal "Test content", hash[:content]
        assert_equal "Narrator", hash[:name]
        assert_equal :main_prompt, hash[:slot]
        assert_equal true, hash[:enabled]
        assert_equal :relative, hash[:insertion_point]
        assert_equal 0, hash[:depth]
        assert_equal 100, hash[:order]
        assert_equal 50, hash[:priority]
        assert_equal :system, hash[:token_budget_group]
        assert_equal [:core], hash[:tags]
        assert_equal({ key: "value" }, hash[:metadata])
      end

      def test_with_creates_new_block_with_overrides
        original = Block.new(
          id: "original-id",
          role: :system,
          content: "Original content",
          slot: :main_prompt,
          priority: 10,
        )

        modified = original.with(content: "Modified content", priority: 20)

        # Original unchanged
        assert_equal "Original content", original.content
        assert_equal 10, original.priority

        # New block has overrides
        assert_equal "Modified content", modified.content
        assert_equal 20, modified.priority

        # Other attributes preserved
        assert_equal :system, modified.role
        assert_equal :main_prompt, modified.slot
      end

      def test_disable_creates_disabled_copy
        original = Block.new(role: :system, content: "Test", enabled: true)
        disabled = original.disable

        assert original.enabled?
        refute disabled.enabled?
        assert_equal original.content, disabled.content
        refute_equal original.object_id, disabled.object_id
      end

      def test_enable_creates_enabled_copy
        original = Block.new(role: :system, content: "Test", enabled: false)
        enabled = original.enable

        refute original.enabled?
        assert enabled.enabled?
        assert_equal original.content, enabled.content
        refute_equal original.object_id, enabled.object_id
      end

      def test_auto_generated_id_is_uuid
        block = Block.new(role: :system, content: "Test")
        # UUID format: 8-4-4-4-12 hex characters
        assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/, block.id)
      end

      def test_content_coerced_to_string
        assert_raises(ArgumentError) do
          Block.new(role: :system, content: 123)
        end
      end

      def test_metadata_is_duplicated
        original_metadata = { key: "value" }
        block = Block.new(role: :system, content: "", metadata: original_metadata)

        # Modifying original doesn't affect block
        original_metadata[:new_key] = "new_value"
        refute block.metadata.key?(:new_key)
      end

      def test_constants
        assert_includes Block::ROLES, :system
        assert_includes Block::ROLES, :user
        assert_includes Block::ROLES, :assistant

        assert_includes Block::INSERTION_POINTS, :relative
        assert_includes Block::INSERTION_POINTS, :in_chat
        assert_includes Block::INSERTION_POINTS, :before_char_defs
        assert_includes Block::INSERTION_POINTS, :after_char_defs
        assert_includes Block::INSERTION_POINTS, :before_example_messages
        assert_includes Block::INSERTION_POINTS, :after_example_messages
        assert_includes Block::INSERTION_POINTS, :top_of_an
        assert_includes Block::INSERTION_POINTS, :bottom_of_an
        assert_includes Block::INSERTION_POINTS, :outlet

        assert_includes Block::BUDGET_GROUPS, :system
        assert_includes Block::BUDGET_GROUPS, :examples
        assert_includes Block::BUDGET_GROUPS, :lore
        assert_includes Block::BUDGET_GROUPS, :history
        assert_includes Block::BUDGET_GROUPS, :custom
        assert_includes Block::BUDGET_GROUPS, :default
      end
    end
  end
end
