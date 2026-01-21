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
        create_active_round!(queue_ids: [@ai_character1.id, @ai_character3.id, @ai_character2.id], current_position: 0)

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        # Should return upcoming speakers from persisted queue (after current)
        expected_ids = [@ai_character3.id, @ai_character2.id]
        assert_equal expected_ids, queue.map(&:id)
      end

      test "returns predicted queue when idle" do
        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        # For list order, should return all in position order
        assert_equal 3, queue.size
        assert_equal @ai_character1.id, queue[0].id
      end

      test "respects limit parameter" do
        queue = QueuePreview.execute(conversation: @conversation, limit: 2)

        assert_equal 2, queue.size
      end

      test "excludes non-respondable members from preview" do
        @ai_character1.update!(participation: "muted")

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        assert_not queue.map(&:id).include?(@ai_character1.id)
      end

      test "excludes exhausted auto users from preview" do
        persona = Character.create!(
          name: "Auto Persona",
          personality: "Test",
          data: { "name" => "Auto Persona" },
          spec_version: 2,
          file_sha256: "auto_persona_#{SecureRandom.hex(8)}",
          status: "ready",
          visibility: "private"
        )

        @user_membership.update!(
          character: persona,
          auto: "auto",
          auto_remaining_steps: 1
        )

        # Defensive: simulate legacy/invalid data where mode is still full but quota is exhausted.
        @user_membership.update_column(:auto_remaining_steps, 0)

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        assert_not queue.map(&:id).include?(@user_membership.id)
      end

      test "list order preview rotates from previous speaker" do
        # Set up with previous speaker
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I just spoke"
        )

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        # Should rotate, starting after character1
        assert_equal @ai_character2.id, queue.first.id
      end

      test "list order preview ignores hidden last speaker" do
        @conversation.messages.create!(
          space_membership: @ai_character1,
          role: "assistant",
          content: "I just spoke (but hidden)",
          visibility: "hidden"
        )

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        # Hidden messages are not scheduler-visible, so we should NOT rotate.
        assert_equal @ai_character1.id, queue.first.id
      end

      test "natural order preview sorts by talkativeness" do
        @space.update!(reply_order: "natural")
        @ai_character1.update!(talkativeness_factor: 0.3)
        @ai_character2.update!(talkativeness_factor: 0.9)
        @ai_character3.update!(talkativeness_factor: 0.6)

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        # Should be sorted by talkativeness descending
        assert_equal @ai_character2.id, queue.first.id
      end

      test "natural order preview considers character card talkativeness when membership uses default" do
        @space.update!(reply_order: "natural")

        talkative =
          Character.create!(
            name: "Preview Talkative",
            user: @user,
            status: "ready",
            visibility: "private",
            spec_version: 2,
            file_sha256: "preview_talkative_#{SecureRandom.hex(8)}",
            data: {
              name: "Preview Talkative",
              group_only_greetings: [],
              extensions: { talkativeness: 0.9 },
            }
          )

        membership =
          @space.space_memberships.create!(
            kind: "character",
            role: "member",
            character: talkative,
            position: 99,
            talkativeness_factor: nil
          )

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        assert_equal membership.id, queue.first.id
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

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        # Idle preview shows the full eligible pool, rotated away from the previous speaker.
        assert_equal 3, queue.size
        assert_includes queue.map(&:id), @ai_character1.id
        assert_equal @ai_character2.id, queue.first.id
      end

      test "returns empty queue when active round has no upcoming speakers" do
        @space.update!(reply_order: "pooled")

        create_active_round!(queue_ids: [@ai_character1.id], current_position: 0)

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        assert_empty queue
      end

      test "manual order preview returns all candidates" do
        @space.update!(reply_order: "manual")

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        # Should show all candidates
        assert_equal 3, queue.size
      end

      test "persisted queue filters out members that became non-schedulable mid-round" do
        create_active_round!(queue_ids: [@ai_character1.id, @ai_character2.id, @ai_character3.id], current_position: 0)

        @ai_character2.update!(participation: "muted")

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        assert_equal [@ai_character3.id], queue.map(&:id)
      end

      test "handles empty queue gracefully" do
        @ai_character1.update!(participation: "muted")
        @ai_character2.update!(participation: "muted")
        @ai_character3.update!(participation: "muted")

        queue = QueuePreview.execute(conversation: @conversation, limit: 10)

        assert_empty queue
      end

      private

      def create_active_round!(queue_ids:, current_position:)
        round =
          ConversationRound.create!(
            conversation: @conversation,
            status: "active",
            scheduling_state: "ai_generating",
            current_position: current_position.to_i
          )

        queue_ids.each_with_index do |membership_id, idx|
          round.participants.create!(
            space_membership_id: membership_id,
            position: idx
          )
        end

        round
      end
    end
  end
end
