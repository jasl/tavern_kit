# frozen_string_literal: true

require "test_helper"

module TurnScheduler
  module Queries
    class QueuePreviewTest < ActiveSupport::TestCase
      setup do
        @user = users(:admin)
        @space = Spaces::Playground.create!(
          name: "QueuePreview Test Space",
          owner: @user,
          reply_order: "list"
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
          position: 1
        )
        @ai_character2 = @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: characters(:ready_v3),
          position: 2
        )
        @ai_character3 = @space.space_memberships.create!(
          kind: "character",
          role: "member",
          character: Character.create!(
            name: "Third Char",
            personality: "Test",
            data: { "name" => "Third Char" },
            spec_version: 2,
            file_sha256: "third_#{SecureRandom.hex(8)}",
            status: "ready",
            visibility: "private"
          ),
          position: 3
        )
      end

      test "returns persisted queue when round is active" do
        # Set up active round with specific queue
        @conversation.update!(
          scheduling_state: "ai_generating",
          current_round_id: SecureRandom.uuid,
          current_speaker_id: @ai_character1.id,
          round_position: 0,
          round_queue_ids: [@ai_character1.id, @ai_character3.id, @ai_character2.id]
        )

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # Should return upcoming speakers from persisted queue (after current)
        expected_ids = [@ai_character3.id, @ai_character2.id]
        assert_equal expected_ids, queue.map(&:id)
      end

      test "returns predicted queue when idle" do
        @conversation.update!(scheduling_state: "idle")

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # For list order, should return all in position order
        assert_equal 3, queue.size
        assert_equal @ai_character1.id, queue[0].id
      end

      test "respects limit parameter" do
        queue = QueuePreview.call(conversation: @conversation, limit: 2)

        assert_equal 2, queue.size
      end

      test "excludes non-respondable members from preview" do
        @ai_character1.update!(participation: "muted")

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        assert_not queue.map(&:id).include?(@ai_character1.id)
      end

      test "excludes exhausted full copilot users from preview" do
        persona = Character.create!(
          name: "Copilot Persona",
          personality: "Test",
          data: { "name" => "Copilot Persona" },
          spec_version: 2,
          file_sha256: "copilot_persona_#{SecureRandom.hex(8)}",
          status: "ready",
          visibility: "private"
        )

        @user_membership.update!(
          character: persona,
          copilot_mode: "full",
          copilot_remaining_steps: 1
        )

        # Defensive: simulate legacy/invalid data where mode is still full but quota is exhausted.
        @user_membership.update_column(:copilot_remaining_steps, 0)

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        assert_not queue.map(&:id).include?(@user_membership.id)
      end

      test "list order preview rotates from previous speaker" do
        # Set up with previous speaker
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I just spoke"
        )

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # Should rotate, starting after character1
        assert_equal @ai_character2.id, queue.first.id
      end

      test "natural order preview sorts by talkativeness" do
        @space.update!(reply_order: "natural")
        @ai_character1.update!(talkativeness_factor: 0.3)
        @ai_character2.update!(talkativeness_factor: 0.9)
        @ai_character3.update!(talkativeness_factor: 0.6)

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # Should be sorted by talkativeness descending
        assert_equal @ai_character2.id, queue.first.id
      end

      test "pooled order preview excludes already spoken in epoch" do
        @space.update!(reply_order: "pooled")

        # Create user message (epoch start)
        @conversation.messages.create!(
          space_membership: @user_membership,
          role: "user",
          content: "Epoch start"
        )

        # Character1 speaks
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I spoke"
        )

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # Character1 should be excluded
        assert_not queue.map(&:id).include?(@ai_character1.id)
      end

      test "manual order preview returns all candidates" do
        @space.update!(reply_order: "manual")

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # Should show all candidates
        assert_equal 3, queue.size
      end

      test "persisted queue filters out members that became non-schedulable mid-round" do
        @conversation.update!(
          scheduling_state: "ai_generating",
          current_round_id: SecureRandom.uuid,
          current_speaker_id: @ai_character1.id,
          round_position: 0,
          round_queue_ids: [@ai_character1.id, @ai_character2.id, @ai_character3.id]
        )

        @ai_character2.update!(participation: "muted")

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        assert_equal [@ai_character3.id], queue.map(&:id)
      end

      test "handles empty queue gracefully" do
        @ai_character1.update!(participation: "muted")
        @ai_character2.update!(participation: "muted")
        @ai_character3.update!(participation: "muted")

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        assert_empty queue
      end

      test "handles missing members in persisted queue" do
        # Set up active round with a deleted member
        @conversation.update!(
          scheduling_state: "ai_generating",
          current_round_id: SecureRandom.uuid,
          current_speaker_id: @ai_character1.id,
          round_position: 0,
          round_queue_ids: [@ai_character1.id, 999999, @ai_character2.id]
        )

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # Should skip the missing member
        assert_not queue.map(&:id).include?(999999)
        assert queue.map(&:id).include?(@ai_character2.id)
      end

      test "uses correct position when current_speaker differs from queue index" do
        # Set up round where current_speaker_id doesn't match position in queue
        @conversation.update!(
          scheduling_state: "ai_generating",
          current_round_id: SecureRandom.uuid,
          current_speaker_id: @ai_character2.id,
          round_position: 0, # Position says 0 but speaker is char2
          round_queue_ids: [@ai_character1.id, @ai_character2.id, @ai_character3.id]
        )

        queue = QueuePreview.call(conversation: @conversation, limit: 10)

        # Should use actual speaker position (index 1), so upcoming is char3
        assert_equal [@ai_character3.id], queue.map(&:id)
      end
    end
  end
end
