# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Queries
    class ActivatedQueueTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space = Spaces::Playground.create!(
          name: "ActivatedQueue Test Space",
          owner: @user,
          reply_order: "natural"
        )
        @conversation = @space.conversations.create!(title: "Main")
        @user_membership = @space.space_memberships.create!(
          kind: "human",
          role: "owner",
          user: @user,
          position: 0
        )
        @ai_character1 = @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v2),
          position: 1,
          talkativeness_factor: 0.8
        )
        @ai_character2 = @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v3),
          position: 2,
          talkativeness_factor: 0.5
        )
      end

      # =========================================================================
      # Natural Order Tests (ST/Risu compatible)
      # =========================================================================

      test "natural order activates speakers based on content and talkativeness" do
        # Use deterministic RNG
        rng = Random.new(42)

        # Create trigger message
        trigger = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello everyone, what do you think?"
        )

        queue = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: trigger,
          is_user_input: true,
          rng: rng
        )

        # Natural order should return at least one speaker
        assert queue.any?, "Queue should have at least one speaker"
        # All returned speakers should be AI characters (can_auto_respond?)
        queue.each do |member|
          assert member.can_auto_respond?, "All queue members should be able to auto respond"
        end
      end

      test "natural order uses talkativeness for activation" do
        # Set one character to always talk, other to never
        @ai_character1.update!(talkativeness_factor: 1.0)
        @ai_character2.update!(talkativeness_factor: 0.0)

        # Create trigger without mentions
        trigger = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello everyone!"
        )

        # Run multiple times to verify talkativeness affects selection
        times_char1_activated = 0
        10.times do |i|
          rng = Random.new(i)
          queue = ActivatedQueue.call(
            conversation: @conversation,
            trigger_message: trigger,
            is_user_input: true,
            rng: rng
          )
          times_char1_activated += 1 if queue.any? { |m| m.id == @ai_character1.id }
        end

        # Character with talkativeness=1.0 should always be activated
        assert_equal 10, times_char1_activated
      end

      test "natural order reads talkativeness from character card extensions when membership is default" do
        char1 =
          Character.create!(
            name: "Card Talkativeness 1.0",
            user: @user,
            status: "ready",
            visibility: "private",
            spec_version: 2,
            file_sha256: "card_talk_1_#{SecureRandom.hex(8)}",
            data: {
              name: "Card Talkativeness 1.0",
              group_only_greetings: [],
              extensions: { talkativeness: 1.0 },
            }
          )
        char2 =
          Character.create!(
            name: "Card Talkativeness 0.0",
            user: @user,
            status: "ready",
            visibility: "private",
            spec_version: 2,
            file_sha256: "card_talk_0_#{SecureRandom.hex(8)}",
            data: {
              name: "Card Talkativeness 0.0",
              group_only_greetings: [],
              extensions: { talkativeness: 0.0 },
            }
          )

        m1 =
          @space.space_memberships.create!(
            kind: "character",
            role: "member",
            character: char1,
            position: 10,
            talkativeness_factor: nil
          )
        @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: char2,
          position: 11,
          talkativeness_factor: nil
        )

        trigger = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello everyone!"
        )

        times_activated = 0
        10.times do |i|
          queue = ActivatedQueue.call(
            conversation: @conversation,
            trigger_message: trigger,
            is_user_input: true,
            rng: Random.new(i)
          )
          times_activated += 1 if queue.any? { |m| m.id == m1.id }
        end

        assert_equal 10, times_activated
      end

      test "natural order bans self-response when allow_self_responses is false" do
        @space.update!(allow_self_responses: false)

        # Set talkativeness so char2 would be selected if not banned
        @ai_character1.update!(talkativeness_factor: 1.0)
        @ai_character2.update!(talkativeness_factor: 1.0)

        # Create assistant message from character1
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I said something"
        )

        # Non-user input should ban last speaker
        queue = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: false,
          rng: Random.new(42)
        )

        assert queue.any?, "Queue should have speakers"
        # Character1 should be banned from being first (self-response not allowed)
        # Note: Character1 might still be in queue if activated by talkativeness,
        # but should not be first
        if queue.size >= 2
          # If multiple speakers, char1 should not be first
          assert_not_equal @ai_character1.id, queue.first.id,
            "Last speaker should not be first when allow_self_responses is false"
        else
          # If only one speaker, it should not be char1
          assert_not_equal @ai_character1.id, queue.first.id,
            "Last speaker should be banned when allow_self_responses is false"
        end
      end

      test "natural order self-response ban ignores hidden last speaker" do
        @space.update!(allow_self_responses: false)

        # Ensure only character1 would be activated, so the test is deterministic.
        @ai_character1.update!(talkativeness_factor: 1.0)
        @ai_character2.update!(talkativeness_factor: 0.0)

        # Create assistant message from character1, but hide it.
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I said something (but hidden)",
          visibility: "hidden"
        )

        queue = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: false,
          rng: Random.new(42)
        )

        assert_equal @ai_character1.id, queue.first.id
      end

      test "natural order allows self-response when allow_self_responses is true" do
        @space.update!(allow_self_responses: true)
        @ai_character1.update!(talkativeness_factor: 1.0)
        @ai_character2.update!(talkativeness_factor: 0.0)

        # Create assistant message from character1
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I said something"
        )

        # Run with deterministic RNG
        queue = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: nil,
          is_user_input: false,
          rng: Random.new(42)
        )

        # Character1 should be allowed (high talkativeness)
        assert queue.any? { |m| m.id == @ai_character1.id }
      end

      test "natural order fallback picks one when none activated" do
        # Set all to zero talkativeness
        @ai_character1.update!(talkativeness_factor: 0.0)
        @ai_character2.update!(talkativeness_factor: 0.0)

        trigger = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello!"
        )

        queue = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: trigger,
          is_user_input: true,
          rng: Random.new(42)
        )

        # Should still pick at least one
        assert queue.any?, "Should have fallback selection"
      end

      # =========================================================================
      # List Order Tests
      # =========================================================================

      test "list order returns all eligible in position order" do
        @space.update!(reply_order: "list")

        queue = ActivatedQueue.call(
          conversation: @conversation,
          is_user_input: true,
          rng: Random.new(42)
        )

        assert_equal 2, queue.size
        assert_equal @ai_character1.id, queue[0].id
        assert_equal @ai_character2.id, queue[1].id
      end

      test "list order excludes muted members" do
        @space.update!(reply_order: "list")
        @ai_character1.update!(participation: "muted")

        queue = ActivatedQueue.call(
          conversation: @conversation,
          is_user_input: true,
          rng: Random.new(42)
        )

        assert_equal 1, queue.size
        assert_equal @ai_character2.id, queue.first.id
      end

      # =========================================================================
      # Pooled Order Tests
      # =========================================================================

      test "pooled order picks one speaker not spoken since last user message" do
        @space.update!(reply_order: "pooled")

        # User message starts epoch
        @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Start epoch"
        )

        # Character1 speaks
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I spoke"
        )

        queue = ActivatedQueue.call(
          conversation: @conversation,
          is_user_input: false,
          rng: Random.new(42)
        )

        # Should pick character2 (hasn't spoken)
        assert_equal 1, queue.size
        assert_equal @ai_character2.id, queue.first.id
      end

      test "pooled order picks random when all have spoken" do
        @space.update!(reply_order: "pooled")

        # User message
        @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Start epoch"
        )

        # Both characters speak
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I spoke"
        )
        @conversation.messages.create!(
          space_membership: @ai_character2,
          role: "assistant",
          content: "I also spoke"
        )

        queue = ActivatedQueue.call(
          conversation: @conversation,
          is_user_input: false,
          rng: Random.new(42)
        )

        # Should pick one (random fallback)
        assert_equal 1, queue.size
      end

      test "pooled order avoids immediate repeat when all have spoken" do
        @space.update!(reply_order: "pooled")

        # User message
        @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Start epoch"
        )

        # Both characters speak, character1 last
        @conversation.messages.create!(
          space_membership: @ai_character2,
          role: "assistant",
          content: "I spoke first"
        )
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I spoke last"
        )

        # Run multiple times to verify no immediate repeat
        repeat_count = 0
        10.times do |i|
          queue = ActivatedQueue.call(
            conversation: @conversation,
            is_user_input: false,
            rng: Random.new(i)
          )
          repeat_count += 1 if queue.first.id == @ai_character1.id
        end

        # Should mostly avoid immediate repeat (char1 was last)
        assert repeat_count < 10, "Should avoid immediate repeat"
      end

      # =========================================================================
      # Manual Order Tests
      # =========================================================================

      test "manual order returns empty for user input" do
        @space.update!(reply_order: "manual")

        trigger = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello!"
        )

        queue = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: trigger,
          is_user_input: true,
          rng: Random.new(42)
        )

        assert_empty queue, "Manual mode should not auto-trigger on user input"
      end

      test "manual order picks one random for non-user input" do
        @space.update!(reply_order: "manual")

        queue = ActivatedQueue.call(
          conversation: @conversation,
          is_user_input: false,
          rng: Random.new(42)
        )

        assert_equal 1, queue.size
      end

      # =========================================================================
      # Edge Cases
      # =========================================================================

      test "returns empty when no eligible candidates" do
        @ai_character1.update!(participation: "muted")
        @ai_character2.update!(participation: "muted")

        queue = ActivatedQueue.call(
          conversation: @conversation,
          is_user_input: true,
          rng: Random.new(42)
        )

        assert_empty queue
      end

      test "deterministic with same RNG seed" do
        trigger = @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Hello!"
        )

        queue1 = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: trigger,
          is_user_input: true,
          rng: Random.new(12345)
        )

        queue2 = ActivatedQueue.call(
          conversation: @conversation,
          trigger_message: trigger,
          is_user_input: true,
          rng: Random.new(12345)
        )

        assert_equal queue1.map(&:id), queue2.map(&:id)
      end
    end
  end
end
