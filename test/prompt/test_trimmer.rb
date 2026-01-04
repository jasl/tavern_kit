# frozen_string_literal: true

require "test_helper"

module TavernKit
  module Prompt
    class TestTrimmer < Minitest::Test
      FakeEstimator = Class.new(TokenEstimator::Base) do
        def estimate(_content)
          1
        end
      end

      CountingEstimator = Class.new(TokenEstimator::Base) do
        attr_reader :calls

        def initialize
          @calls = 0
        end

        def estimate(_content)
          @calls += 1
          1
        end
      end

      def test_trim_disables_oldest_history_block_first_including_index_zero
        blocks = [
          Block.new(role: :user, content: "H0", token_budget_group: :history, order: 0),
          Block.new(role: :assistant, content: "H1", token_budget_group: :history, order: 1),
          Block.new(role: :assistant, content: "H2", token_budget_group: :history, order: 2),
        ]
        plan = Plan.new(blocks: blocks)

        trimmer = Trimmer.new(token_estimator: FakeEstimator.new, message_overhead: 0)
        report = trimmer.trim!(plan, max_tokens: 2)

        assert report[:trimmed]
        assert report[:fits]
        assert_equal 1, report[:removed_history_messages]

        # Oldest history block (index 0) must be disabled first.
        assert plan.blocks[0].disabled?
        assert plan.blocks[1].enabled?
        assert plan.blocks[2].enabled?

        assert_equal 3, plan.size
        assert_equal 2, plan.enabled_size
      end

      def test_trim_does_not_reestimate_entire_plan_each_eviction
        blocks = (1..200).map do |i|
          Block.new(role: :user, content: "X", token_budget_group: :history, order: i)
        end
        plan = Plan.new(blocks: blocks)

        estimator = CountingEstimator.new
        trimmer = Trimmer.new(token_estimator: estimator, message_overhead: 0)
        report = trimmer.trim!(plan, max_tokens: 10)

        assert report[:trimmed]
        assert report[:fits]
        assert_operator estimator.calls, :<=, 250
      end

      def test_examples_evicted_by_priority_not_example_block_index
        # Two example dialogues (example_block 0 and 1), but example_block 1 has higher priority
        # and should be evicted first.
        blocks = [
          Block.new(
            role: :system,
            content: "EX0-A",
            token_budget_group: :examples,
            priority: 1,
            order: 0,
            metadata: { example_block: 0 },
          ),
          Block.new(
            role: :system,
            content: "EX0-B",
            token_budget_group: :examples,
            priority: 1,
            order: 1,
            metadata: { example_block: 0 },
          ),
          Block.new(
            role: :system,
            content: "EX1-A",
            token_budget_group: :examples,
            priority: 100,
            order: 2,
            metadata: { example_block: 1 },
          ),
          Block.new(
            role: :system,
            content: "EX1-B",
            token_budget_group: :examples,
            priority: 100,
            order: 3,
            metadata: { example_block: 1 },
          ),
        ]

        plan = Plan.new(blocks: blocks)

        trimmer = Trimmer.new(token_estimator: FakeEstimator.new, message_overhead: 0)
        report = trimmer.trim!(plan, max_tokens: 2)

        assert report[:trimmed]
        assert report[:fits]

        # Evict the higher priority example dialogue first.
        assert_equal [1], report[:removed_example_blocks]

        assert plan.blocks.select { |b| b.metadata[:example_block] == 1 }.all?(&:disabled?)
        assert plan.blocks.select { |b| b.metadata[:example_block] == 0 }.all?(&:enabled?)
      end

      # Integration test: trim evicts non-constant lore before constant lore
      def test_trim_with_lore_eviction_priority
        # Create a plan with constant and non-constant lore blocks
        blocks = [
          Block.new(
            role: :system,
            content: "NON_CONST",
            token_budget_group: :lore,
            priority: 200, # Higher priority = evicted first
            order: 0,
            metadata: { uid: "non_const", constant: false },
          ),
          Block.new(
            role: :system,
            content: "CONST",
            token_budget_group: :lore,
            priority: 100, # Lower priority = kept longer
            order: 1,
            metadata: { uid: "const", constant: true },
          ),
        ]
        plan = Plan.new(blocks: blocks)

        trimmer = Trimmer.new(token_estimator: FakeEstimator.new, message_overhead: 0)
        report = trimmer.trim!(plan, max_tokens: 1)

        assert report[:trimmed]
        assert report[:fits]
        assert_equal ["non_const"], report[:removed_lore_uids]

        assert plan.blocks.find { |b| b.metadata[:uid] == "non_const" }.disabled?
        assert plan.blocks.find { |b| b.metadata[:uid] == "const" }.enabled?
      end

      def test_trim_with_example_insertion_order_priority
        # Example blocks with different priorities based on insertion order
        blocks = [
          Block.new(
            role: :system,
            content: "LOW",
            token_budget_group: :examples,
            priority: 200, # Higher priority = evicted first (lower insertion_order)
            order: 0,
            metadata: { uid: "low", example_block: "low" },
          ),
          Block.new(
            role: :system,
            content: "HIGH",
            token_budget_group: :examples,
            priority: 100, # Lower priority = kept longer (higher insertion_order)
            order: 1,
            metadata: { uid: "high", example_block: "high" },
          ),
        ]
        plan = Plan.new(blocks: blocks)

        trimmer = Trimmer.new(token_estimator: FakeEstimator.new, message_overhead: 0)
        report = trimmer.trim!(plan, max_tokens: 1)

        assert report[:trimmed]
        assert report[:fits]
        # Example blocks are tracked in removed_example_blocks by their example_block key
        assert_equal 1, report[:removed_example_blocks].size
        assert_equal "low", report[:removed_example_blocks].first
      end
    end
  end
end
