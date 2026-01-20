# frozen_string_literal: true

require "test_helper"

# Tests for SpaceMembership concurrent access patterns.
#
# These tests verify that:
# - decrement_auto_remaining_steps! correctly decrements without double-counting
# - SettingsPatch handles optimistic lock conflicts correctly
#
class SpaceMembershipConcurrencyTest < ActiveSupport::TestCase
  setup do
    # Pre-seed default settings to avoid race conditions in parallel tests
    Setting.set("llm.default_provider_id", LLMProvider.first&.id || "1") if Setting.find_by(key: "llm.default_provider_id").nil?
    Setting.set("preset.default_id", Preset.first&.id || "1") if Setting.find_by(key: "preset.default_id").nil?

    @user = users(:admin)
    @character = characters(:ready_v2)
    @space = Spaces::Playground.create!(name: "Membership Test Space", owner: @user)

    # Auto mode requires both user and character
    @membership = @space.space_memberships.create!(
      user: @user,
      character: @character,
      role: "member",
      status: "active",
      auto: "auto",
      auto_remaining_steps: 10  # MAX_AUTO_STEPS is 10
    )
  end

  # ============================================================
  # Auto Steps Decrement
  # ============================================================

  test "concurrent decrement_auto_remaining_steps decrements exactly N times for N calls" do
    initial_steps = 10  # MAX_AUTO_STEPS is 10
    @membership.update!(auto_remaining_steps: initial_steps)

    decrement_count = 5  # Fewer than initial steps to test partial decrement
    barrier = Concurrent::CyclicBarrier.new(decrement_count)
    results = Concurrent::Array.new
    membership_id = @membership.id

    # Stub broadcasts to avoid side effects
    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    Messages::Broadcasts.stubs(:broadcast_auto_steps_updated)

    threads = decrement_count.times.map do
      Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          membership = SpaceMembership.find(membership_id)
          result = membership.decrement_auto_remaining_steps!
          results << result
        end
      rescue => e
        results << e
      end
    end

    threads.each(&:join)

    # Check for errors
    errors = results.select { |r| r.is_a?(Exception) }
    assert errors.empty?, "No errors should occur: #{errors.map(&:message).join(', ')}"

    # All decrements should succeed
    success_count = results.count(true)
    assert_equal decrement_count, success_count, "All #{decrement_count} decrements should succeed"

    # Final value should be initial - decrement_count
    @membership.reload
    expected_remaining = initial_steps - decrement_count
    assert_equal expected_remaining, @membership.auto_remaining_steps,
      "Steps should be #{expected_remaining} after #{decrement_count} decrements"
    assert_equal "auto", @membership.auto, "Should still be in auto mode"
  end

  test "concurrent decrements stop correctly when steps reach zero" do
    # Start with exactly 3 steps
    initial_steps = 3
    @membership.update!(auto_remaining_steps: initial_steps, auto: "auto")

    # Try to decrement 6 times (more than available)
    attempt_count = 6
    barrier = Concurrent::CyclicBarrier.new(attempt_count)
    results = Concurrent::Array.new
    membership_id = @membership.id

    # Stub the broadcast to avoid side effects
    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    Messages::Broadcasts.stubs(:broadcast_auto_steps_updated)

    threads = attempt_count.times.map do
      Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          membership = SpaceMembership.find(membership_id)
          result = membership.decrement_auto_remaining_steps!
          results << result
        end
      rescue => e
        results << e
      end
    end

    threads.each(&:join)

    # Check for errors
    errors = results.select { |r| r.is_a?(Exception) }
    assert errors.empty?, "No errors should occur: #{errors.map(&:message).join(', ')}"

    # Exactly initial_steps decrements should succeed
    success_count = results.count(true)
    assert_equal initial_steps, success_count,
      "Exactly #{initial_steps} decrements should succeed, got #{success_count}"

    # Remaining should be false (failed decrements)
    failure_count = results.count(false)
    assert_equal attempt_count - initial_steps, failure_count,
      "#{attempt_count - initial_steps} decrements should fail"

    # Final state should have mode "none"
    @membership.reload
    assert_nil @membership.auto_remaining_steps
    assert_equal "none", @membership.auto
  end

  # ============================================================
  # Settings Patch Optimistic Lock
  # ============================================================

  test "concurrent settings patches with same version causes conflict" do
    @membership.update!(settings_version: 1, settings: ConversationSettings::ParticipantSettings.new)

    # Both threads use the same version
    version = @membership.settings_version
    barrier = Concurrent::CyclicBarrier.new(2)
    results = Concurrent::Array.new
    membership_id = @membership.id

    # Use valid schema paths for testing
    prompts = ["Thread 0 prompt", "Thread 1 prompt"]

    threads = 2.times.map do |i|
      Thread.new do
        barrier.wait

        ActiveRecord::Base.connection_pool.with_connection do
          membership = SpaceMembership.find(membership_id)
          patch = SpaceMemberships::SettingsPatch.new(membership)
          result = patch.call({
            "settings_version" => version,
            "settings" => { "preset" => { "main_prompt" => prompts[i] } },
          })
          results << result
        end
      rescue => e
        results << e
      end
    end

    threads.each(&:join)

    # Check for errors
    errors = results.select { |r| r.is_a?(Exception) }
    assert errors.empty?, "No exceptions should occur: #{errors.map(&:message).join(', ')}"

    # One should succeed, one should conflict
    statuses = results.map(&:status)
    assert_includes statuses, :ok, "One request should succeed"
    assert_includes statuses, :conflict, "One request should get conflict"

    # Only one prompt should be saved (the winner's)
    @membership.reload
    saved_prompt = @membership.settings&.preset&.main_prompt
    assert prompts.include?(saved_prompt), "Saved prompt should be one of the thread's values"
  end

  test "sequential settings patches with correct versions all succeed" do
    @membership.update!(settings_version: 0, settings: ConversationSettings::ParticipantSettings.new)

    results = []

    5.times do |i|
      current_version = @membership.reload.settings_version

      patch = SpaceMemberships::SettingsPatch.new(@membership)
      result = patch.call({
        "settings_version" => current_version,
        "settings" => { "preset" => { "main_prompt" => "Prompt version #{i}" } },
      })
      results << result
    end

    # All should succeed
    assert results.all?(&:ok?), "All sequential patches should succeed"

    # Last prompt should be preserved
    @membership.reload
    assert_equal "Prompt version 4", @membership.settings.preset.main_prompt

    # Version should have incremented 5 times
    assert_equal 5, @membership.settings_version
  end

  test "settings patch with stale version returns conflict" do
    @membership.update!(
      settings_version: 5,
      settings: ConversationSettings::ParticipantSettings.new(
        preset: { main_prompt: "Original" }
      )
    )

    patch = SpaceMemberships::SettingsPatch.new(@membership)
    patch = SpaceMemberships::SettingsPatch.new(@membership)
    result = patch.call({
      "settings_version" => 3, # Stale version
      "settings" => { "preset" => { "main_prompt" => "Should not save" } },
    })

    assert_equal :conflict, result.status
    assert result.body[:conflict]

    # Settings should not have changed
    @membership.reload
    assert_equal 5, @membership.settings_version
    assert_equal "Original", @membership.settings.preset.main_prompt
  end

  # ============================================================
  # Mixed Operations
  # ============================================================

  test "concurrent auto decrements and settings patches do not deadlock" do
    @membership.update!(
      auto_remaining_steps: 10,  # MAX_AUTO_STEPS is 10
      auto: "auto",
      settings_version: 0,
      settings: ConversationSettings::ParticipantSettings.new
    )

    total_threads = 10
    barrier = Concurrent::CyclicBarrier.new(total_threads)
    results = Concurrent::Array.new
    membership_id = @membership.id

    Messages::Broadcasts.stubs(:broadcast_auto_disabled)
    Messages::Broadcasts.stubs(:broadcast_auto_steps_updated)

    threads = []

    # Half do decrements
    5.times do
      threads << Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          membership = SpaceMembership.find(membership_id)
          result = membership.decrement_auto_remaining_steps!
          results << { type: :decrement, result: result }
        end
      rescue => e
        results << { type: :decrement, error: e }
      end
    end

    # Half do settings patches - use valid schema paths
    5.times do |i|
      threads << Thread.new do
        barrier.wait
        ActiveRecord::Base.connection_pool.with_connection do
          membership = SpaceMembership.find(membership_id)
          patch = SpaceMemberships::SettingsPatch.new(membership)
          result = patch.call({
            "settings_version" => membership.settings_version,
            "settings" => { "preset" => { "main_prompt" => "Concurrent #{i}" } },
          })
          results << { type: :patch, result: result }
        end
      rescue => e
        results << { type: :patch, error: e }
      end
    end

    # Should complete without deadlock (timeout would fail the test)
    threads.each { |t| t.join(30) } # 30 second timeout

    # Check all threads completed
    assert threads.all? { |t| !t.alive? }, "All threads should complete (no deadlock)"

    # Check for exceptions (not conflicts, which are expected)
    errors = results.select { |r| r[:error] }
    assert errors.empty?, "No exceptions should occur: #{errors.map { |r| r[:error].message }.join(', ')}"

    # Decrement results should all be booleans
    decrement_results = results.select { |r| r[:type] == :decrement }
    assert decrement_results.all? { |r| [true, false].include?(r[:result]) },
      "All decrement results should be boolean"

    # Patch results should be ok or conflict
    patch_results = results.select { |r| r[:type] == :patch }
    assert patch_results.all? { |r| [:ok, :conflict].include?(r[:result].status) },
      "All patch results should be ok or conflict"
  end
end
