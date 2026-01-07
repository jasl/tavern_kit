# frozen_string_literal: true

require "test_helper"

# Tests for Message swipe-related methods
class MessageSwipesMethodsTest < ActiveSupport::TestCase
  fixtures :users, :characters

  def setup
    @space = Spaces::Playground.create!(name: "Test Space", owner: users(:admin))
    @conversation = @space.conversations.create!(title: "Main")
    @membership =
      @space.space_memberships.create!(
        kind: "character",
        character: characters(:ready_v2),
        role: "member",
        position: 0
      )
    @message = @conversation.messages.create!(
      space_membership: @membership,
      role: "assistant",
      content: "Original content",
      metadata: { "original" => true }
    )
  end

  # --- ensure_initial_swipe! tests ---

  test "ensure_initial_swipe! creates swipe from current content when none exist" do
    assert_equal 0, @message.message_swipes_count

    swipe = @message.ensure_initial_swipe!

    assert_equal 1, @message.reload.message_swipes_count
    assert_equal 0, swipe.position
    assert_equal "Original content", swipe.content
    assert_equal @message.active_message_swipe_id, swipe.id
  end

  test "ensure_initial_swipe! returns existing first swipe if present" do
    existing = @message.message_swipes.create!(position: 0, content: "Existing")
    @message.update!(active_message_swipe: existing)

    result = @message.ensure_initial_swipe!

    assert_equal existing.id, result.id
    assert_equal 1, @message.reload.message_swipes_count
  end

  test "ensure_initial_swipe! preserves metadata and conversation_run_id" do
    run = @conversation.conversation_runs.create!(
      kind: "user_turn",
      status: "succeeded",
      reason: "test"
    )
    @message.update!(conversation_run: run, metadata: { "test" => "value" })

    swipe = @message.ensure_initial_swipe!

    assert_equal run.id, swipe.conversation_run_id
    assert_equal({ "test" => "value" }, swipe.metadata)
  end

  # --- add_swipe! tests ---

  test "add_swipe! creates new swipe at next position" do
    @message.ensure_initial_swipe!

    swipe = @message.add_swipe!(
      content: "New version",
      metadata: { "new" => true }
    )

    assert_equal 1, swipe.position
    assert_equal "New version", swipe.content
    assert_equal({ "new" => true }, swipe.metadata)
  end

  test "add_swipe! sets the new swipe as active" do
    @message.ensure_initial_swipe!

    swipe = @message.add_swipe!(content: "New version")

    assert_equal swipe.id, @message.reload.active_message_swipe_id
  end

  test "add_swipe! syncs message content with new swipe" do
    @message.ensure_initial_swipe!

    @message.add_swipe!(content: "New version")

    assert_equal "New version", @message.reload.content
  end

  test "add_swipe! syncs message conversation_run_id with new swipe" do
    @message.ensure_initial_swipe!
    run = @conversation.conversation_runs.create!(kind: "regenerate", status: "succeeded", reason: "test")

    @message.add_swipe!(content: "Regenerated", conversation_run_id: run.id)

    assert_equal run.id, @message.reload.conversation_run_id
  end

  test "add_swipe! creates initial swipe if none exist" do
    assert_equal 0, @message.message_swipes_count

    @message.add_swipe!(content: "New version")

    assert_equal 2, @message.reload.message_swipes_count
    positions = @message.message_swipes.pluck(:position)
    assert_includes positions, 0
    assert_includes positions, 1
  end

  test "add_swipe! handles concurrent access correctly" do
    @message.ensure_initial_swipe!
    message_id = @message.id

    threads = 3.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Message.find(message_id).add_swipe!(content: "Version #{i}")
        end
      end
    end
    threads.each(&:join)

    @message.reload
    assert_equal 4, @message.message_swipes_count
    positions = @message.message_swipes.pluck(:position).sort
    assert_equal [0, 1, 2, 3], positions
  end

  # --- select_swipe! tests ---

  test "select_swipe! navigates left" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")
    @message.add_swipe!(content: "Third")

    # Now at position 2 (Third)
    assert_equal 2, @message.active_message_swipe.position

    selected = @message.select_swipe!(direction: :left)

    assert_equal 1, selected.position
    assert_equal "Second", @message.reload.content
  end

  test "select_swipe! navigates right" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")
    @message.select_swipe!(direction: :left) # Go back to first

    selected = @message.select_swipe!(direction: :right)

    assert_equal 1, selected.position
    assert_equal "Second", @message.reload.content
  end

  test "select_swipe! returns nil at left boundary" do
    @message.ensure_initial_swipe!

    result = @message.select_swipe!(direction: :left)

    assert_nil result
    assert_equal 0, @message.active_message_swipe.position
  end

  test "select_swipe! returns nil at right boundary" do
    @message.ensure_initial_swipe!

    result = @message.select_swipe!(direction: :right)

    assert_nil result
    assert_equal 0, @message.active_message_swipe.position
  end

  test "select_swipe! syncs message content with selected swipe" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")
    @message.select_swipe!(direction: :left)

    assert_equal "Original content", @message.reload.content
  end

  test "select_swipe! syncs message conversation_run_id with selected swipe" do
    run1 = @conversation.conversation_runs.create!(kind: "user_turn", status: "succeeded", reason: "test")
    @message.update!(conversation_run: run1)
    @message.ensure_initial_swipe!

    run2 = @conversation.conversation_runs.create!(kind: "regenerate", status: "succeeded", reason: "test")
    @message.add_swipe!(content: "Second", conversation_run_id: run2.id)

    @message.select_swipe!(direction: :left)

    assert_equal run1.id, @message.reload.conversation_run_id
  end

  # --- select_swipe_at! tests ---

  test "select_swipe_at! selects swipe by position" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")
    @message.add_swipe!(content: "Third")

    selected = @message.select_swipe_at!(1)

    assert_equal 1, selected.position
    assert_equal "Second", @message.reload.content
  end

  test "select_swipe_at! returns nil for non-existent position" do
    @message.ensure_initial_swipe!

    result = @message.select_swipe_at!(99)

    assert_nil result
  end

  # --- swipeable? tests ---

  test "swipeable? returns false when no swipes" do
    assert_not @message.swipeable?
  end

  test "swipeable? returns false with single swipe" do
    @message.ensure_initial_swipe!

    assert_not @message.swipeable?
  end

  test "swipeable? returns true with multiple swipes" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")

    assert @message.swipeable?
  end

  # --- active_swipe_position tests ---

  test "active_swipe_position returns 1-based position" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")

    assert_equal 2, @message.active_swipe_position
  end

  test "active_swipe_position returns 1 when no swipes" do
    assert_equal 1, @message.active_swipe_position
  end

  # --- at_first_swipe? / at_last_swipe? tests ---

  test "at_first_swipe? returns true at position 0" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")
    @message.select_swipe!(direction: :left)

    assert @message.at_first_swipe?
  end

  test "at_first_swipe? returns false at non-zero position" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")

    assert_not @message.at_first_swipe?
  end

  test "at_last_swipe? returns true at highest position" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")

    assert @message.at_last_swipe?
  end

  test "at_last_swipe? returns false when not at highest position" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second")
    @message.select_swipe!(direction: :left)

    assert_not @message.at_last_swipe?
  end

  # --- content sync to active swipe tests ---

  test "editing message content syncs to active swipe" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second version")

    # Verify initial state
    assert_equal "Second version", @message.content
    assert_equal "Second version", @message.active_message_swipe.content

    # Edit message content directly
    @message.update!(content: "Edited content")

    # Active swipe should be synced
    assert_equal "Edited content", @message.content
    assert_equal "Edited content", @message.active_message_swipe.reload.content
  end

  test "editing message without swipes does not create swipes" do
    message = @conversation.messages.create!(
      space_membership: @membership,
      role: "assistant",
      content: "Original"
    )
    assert_equal 0, message.message_swipes_count
    assert_nil message.active_message_swipe

    message.update!(content: "Edited")

    assert_equal 0, message.reload.message_swipes_count
    assert_nil message.active_message_swipe
    assert_equal "Edited", message.content
  end

  test "editing content keeps other swipes unchanged" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second version")
    @message.add_swipe!(content: "Third version")

    # Go back to second version and edit
    @message.select_swipe!(direction: :left)
    assert_equal 1, @message.active_message_swipe.position
    @message.update!(content: "Edited second")

    # The first and third swipes should be unchanged
    first_swipe = @message.message_swipes.find_by(position: 0)
    third_swipe = @message.message_swipes.find_by(position: 2)

    assert_equal "Original content", first_swipe.content
    assert_equal "Third version", third_swipe.content
    assert_equal "Edited second", @message.active_message_swipe.reload.content
  end

  test "content sync does not trigger when content unchanged" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second version")

    original_swipe_updated_at = @message.active_message_swipe.updated_at

    # Update something other than content
    @message.update!(metadata: { "test" => true })

    # Swipe should not have been updated
    assert_equal original_swipe_updated_at, @message.active_message_swipe.reload.updated_at
  end

  test "switching swipes after editing shows correct content" do
    @message.ensure_initial_swipe!
    @message.add_swipe!(content: "Second version")

    # Edit the second version
    @message.update!(content: "Edited second")

    # Switch back to first
    @message.select_swipe!(direction: :left)
    assert_equal "Original content", @message.content

    # Switch to edited second
    @message.select_swipe!(direction: :right)
    assert_equal "Edited second", @message.content
  end
end
