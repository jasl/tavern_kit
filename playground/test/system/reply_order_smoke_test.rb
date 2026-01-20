# frozen_string_literal: true

require "application_system_test_case"

class ReplyOrderSmokeTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  setup do
    @admin = users(:admin)
    @mock_provider = llm_providers(:mock_local)
  end

  def wait_for(timeout: 10, &block)
    Timeout.timeout(timeout) do
      loop do
        break if block.call

        sleep 0.1
      end
    end
  rescue Timeout::Error
    flunk "Timed out waiting for condition"
  end

  def sign_in_as(user)
    visit new_session_url
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button I18n.t("sessions.new.submit")
    assert_text "Welcome to Tavern", wait: 10

    configure_mock_provider_base_url!
  end

  # System tests run the Rails app on a dynamic port.
  # Ensure the Mock (Local) provider points at *this* server so LLM calls work.
  def configure_mock_provider_base_url!
    uri = URI.parse(current_url)
    base = +"#{uri.scheme}://#{uri.host}"
    base << ":#{uri.port}" if uri.port

    # In system tests, prefer non-streaming to avoid long-lived /mock_llm streams
    # exhausting Puma threads (which can manifest as Net::ReadTimeout flakiness).
    @mock_provider.update!(base_url: "#{base}/mock_llm/v1", model: "mock", streamable: false)
    LLMProvider.set_default!(@mock_provider)
  end

  def create_group_chat_space!(reply_order:)
    space = Spaces::Playground.create!(
      name: "ReplyOrder Smoke",
      owner: @admin,
      reply_order: reply_order,
      during_generation_user_input_policy: "reject",
      user_turn_debounce_ms: 0,
      auto_without_human_delay_ms: 0
    )

    space.space_memberships.grant_to(@admin, role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))
    space.space_memberships.grant_to(characters(:ready_v3))

    # Auto (human persona) runs rely on the speaker's effective provider. In system tests,
    # pin the human membership to the same mock provider to avoid flakiness from default
    # provider settings caching.
    space.space_memberships.active.find_by!(user: @admin, kind: "human").update!(llm_provider: @mock_provider)

    space.space_memberships.active.ai_characters.each do |m|
      m.update!(llm_provider: @mock_provider)
    end

    space
  end

  def group_queue_dom_id(conversation)
    dom_id(conversation, :group_queue)
  end

  def group_queue_selector(conversation)
    "##{group_queue_dom_id(conversation)}"
  end

  def expect_next_queue_includes(conversation, names)
    within group_queue_selector(conversation) do
      names.each do |name|
        assert_selector ".avatar[data-tip='#{name}']", wait: 10
      end
    end
  end

  def open_manage_round_modal
    find("button[title='Manage round']", wait: 10).click
    assert_selector "dialog#round_queue_modal[open]", wait: 10
  end

  def close_manage_round_modal
    within "dialog#round_queue_modal" do
      find("form[method='dialog'] button", match: :first, wait: 10).click
    end
    assert_no_selector "dialog#round_queue_modal[open]", wait: 10
  end

  def scheduler_debug_snapshot(space:, conversation:)
    space.reload
    conversation.reload

    ai =
      space.space_memberships
        .where(kind: "character")
        .order(:position)
        .map do |m|
          "#{m.id} name=#{m.display_name.inspect} status=#{m.status} participation=#{m.participation} pos=#{m.position}"
        end

    active_round = conversation.conversation_rounds.find_by(status: "active")
    round =
      if active_round
        participants =
          active_round.participants
            .order(:position)
            .map do |p|
              "#{p.id} member_id=#{p.space_membership_id} pos=#{p.position} status=#{p.status}"
            end

        "active_round id=#{active_round.id} state=#{active_round.scheduling_state.inspect} " \
          "current_position=#{active_round.current_position} meta=#{active_round.metadata.inspect}\n" \
          "participants:\n- #{participants.join("\n- ")}"
      else
        "active_round: none"
      end

    runs =
      conversation.conversation_runs
        .order(:created_at, :id)
        .map do |r|
          "#{r.id} status=#{r.status} kind=#{r.kind} speaker_id=#{r.speaker_space_membership_id} " \
            "round_id=#{r.conversation_round_id} error=#{r.error.inspect} debug=#{r.debug.inspect}"
        end

    <<~MSG
      space_id=#{space.id} reply_order=#{space.reply_order.inspect} allow_self=#{space.allow_self_responses?}
      AI memberships:
      - #{ai.join("\n- ")}
      #{round}
      runs:
      - #{runs.join("\n- ")}
    MSG
  end

  test "reply_order=list: round includes both AI; idle preview shows both; manage modal consistent" do
    sign_in_as(@admin)

    space = create_group_chat_space!(reply_order: "list")
    conversation = space.conversations.create!(title: "List Smoke", kind: "root")

    visit conversation_url(conversation)

    # Send a message but do NOT run jobs yet: we want to observe active round UI.
    fill_in "message[content]", with: "Hello list"
    find("#message_form button[type='submit']", wait: 5).click

    # Group queue should reflect active scheduling.
    within group_queue_selector(conversation) do
      assert_selector ".loading.loading-spinner", wait: 10
      # While generating, only the remaining upcoming speakers should be shown (2 AI total => 1 upcoming).
      assert_selector ".avatar.tooltip:not(.avatar-placeholder)[data-tip]", count: 1, wait: 10
    end

    # Manage round should show an active round (not \"No active round\") and 1 upcoming slot (2 AI total).
    open_manage_round_modal
    within "dialog#round_queue_modal" do
      assert_selector "turbo-frame#round_queue_editor", wait: 10
      assert_text "Current", wait: 10
      assert_text "Upcoming", wait: 10
      assert_selector "[data-sortable-item]", count: 1, wait: 10
    end

    # Now run the queued jobs to completion; list order should produce 2 assistant messages.
    drain_conversation_run_jobs!(conversation)
    assert_selector "[data-message-role='assistant']", minimum: 2, wait: 20

    # Modal should converge to idle state.
    within "dialog#round_queue_modal" do
      assert_text "No active round", wait: 10
    end
    close_manage_round_modal

    # After completion, preview should show both AI characters as upcoming (not just one).
    names = space.space_memberships.active.ai_characters.by_position.pluck(:cached_display_name)
    expect_next_queue_includes(conversation, names)
  end

  test "reply_order=list via UI change: must schedule both AI (not fall back to natural)" do
    sign_in_as(@admin)

    # Start in natural, but make natural deterministic: exactly 1 speaker.
    space = create_group_chat_space!(reply_order: "natural")
    ai = space.space_memberships.active.ai_characters.by_position.to_a
    ai[0].update!(talkativeness_factor: 1.0)
    ai[1].update!(talkativeness_factor: 0.0)

    conversation = space.conversations.create!(title: "List via UI Smoke", kind: "root")

    visit conversation_url(conversation)

    # Switch to the Chat tab in the right sidebar, then change reply_order via the real PATCH /playgrounds/:id path.
    within "#llm_settings_panel" do
      find("button[role='tab'][data-tab='space']", wait: 10).click
      find("select[name='playground[reply_order]']", wait: 10).find("option[value='list']").select_option
    end

    wait_for(timeout: 10) { space.reload.reply_order == "list" }

    # Send a message but do NOT run jobs yet: we want to observe active round UI + DB state.
    fill_in "message[content]", with: "Hello list via UI"
    find("#message_form button[type='submit']", wait: 5).click
    assert_selector "[data-message-role='user']", text: "Hello list via UI", wait: 10

    wait_for(timeout: 10) { conversation.reload.conversation_rounds.where(status: "active").exists? }

    active_round = conversation.conversation_rounds.find_by(status: "active")
    assert active_round, scheduler_debug_snapshot(space: space, conversation: conversation)
    assert_equal 2, active_round.participants.count, scheduler_debug_snapshot(space: space, conversation: conversation)
    assert_equal "list", active_round.metadata&.dig("reply_order"), scheduler_debug_snapshot(space: space, conversation: conversation)

    # While generating, toolbar should show only the remaining upcoming speaker (2 AI total => 1 upcoming).
    within group_queue_selector(conversation) do
      assert_selector ".loading.loading-spinner", wait: 10
      assert_selector ".avatar.tooltip:not(.avatar-placeholder)[data-tip]", count: 1, wait: 10
    end

    # Manage modal should reflect the same active round state and show 1 upcoming slot.
    open_manage_round_modal
    within "dialog#round_queue_modal" do
      assert_selector "turbo-frame#round_queue_editor", wait: 10
      assert_text "Current", wait: 10
      assert_text "Upcoming", wait: 10
      assert_selector "[data-sortable-item]", count: 1, wait: 10
    end

    drain_conversation_run_jobs!(conversation)
    assert_selector "[data-message-role='assistant']", minimum: 2, wait: 20

    within "dialog#round_queue_modal" do
      assert_text "No active round", wait: 10
    end
    close_manage_round_modal
  end

  test "reply_order=natural: deterministic multi-speaker when talkativeness=1; idle preview shows both" do
    sign_in_as(@admin)

    space = create_group_chat_space!(reply_order: "natural")
    space.space_memberships.active.ai_characters.each { |m| m.update!(talkativeness_factor: 1.0) }
    conversation = space.conversations.create!(title: "Natural Smoke", kind: "root")

    visit conversation_url(conversation)

    fill_in "message[content]", with: "Hello natural"
    find("#message_form button[type='submit']", wait: 5).click
    assert_selector "[data-message-role='user']", text: "Hello natural", wait: 10

    within group_queue_selector(conversation) do
      assert_selector ".loading.loading-spinner", wait: 10
      # While generating, only the remaining upcoming speakers should be shown (2 AI total => 1 upcoming).
      assert_selector ".avatar.tooltip:not(.avatar-placeholder)[data-tip]", count: 1, wait: 10
    end

    # Manage modal should reflect the same active round state.
    open_manage_round_modal
    within "dialog#round_queue_modal" do
      assert_selector "turbo-frame#round_queue_editor", wait: 10
      assert_text "Current", wait: 10
      assert_text "Upcoming", wait: 10
      assert_selector "[data-sortable-item]", count: 1, wait: 10
    end

    drain_conversation_run_jobs!(conversation)

    # With talkativeness=1.0 for both AIs, natural activation should schedule both.
    assert_selector "[data-message-role='assistant']", minimum: 2, wait: 20

    within "dialog#round_queue_modal" do
      assert_text "No active round", wait: 10
    end
    close_manage_round_modal

    names = space.space_memberships.active.ai_characters.by_position.pluck(:cached_display_name)
    expect_next_queue_includes(conversation, names)
  end

  test "reply_order=pooled: exactly one AI responds per user message" do
    sign_in_as(@admin)

    space = create_group_chat_space!(reply_order: "pooled")
    conversation = space.conversations.create!(title: "Pooled Smoke", kind: "root")

    visit conversation_url(conversation)

    fill_in "message[content]", with: "Hello pooled"
    find("#message_form button[type='submit']", wait: 5).click
    assert_selector "[data-message-role='user']", text: "Hello pooled", wait: 10

    within group_queue_selector(conversation) do
      assert_selector ".loading.loading-spinner", wait: 10
      # Pooled is a single-speaker round; we should still show a stable Next placeholder (not disappear).
      assert_selector "[data-group-queue-next-empty]", wait: 10
    end

    open_manage_round_modal
    within "dialog#round_queue_modal" do
      assert_selector "turbo-frame#round_queue_editor", wait: 10
      assert_text "Current", wait: 10
      assert_text "Upcoming", wait: 10
      assert_no_selector "[data-sortable-item]", wait: 10
      assert_text "No upcoming speakers in this round.", wait: 10
    end

    drain_conversation_run_jobs!(conversation)

    assert_selector "[data-message-role='assistant']", count: 1, wait: 20

    # Ensure the pooled responder was one of the AI characters.
    within all("[data-message-role='assistant']").last do
      assert_selector ".mes-name", text: /Ready V2 Character|Ready V3 Character/
    end

    within "dialog#round_queue_modal" do
      assert_text "No active round", wait: 10
    end
    close_manage_round_modal

    names = space.space_memberships.active.ai_characters.by_position.pluck(:cached_display_name)
    expect_next_queue_includes(conversation, names)
  end

  test "reply_order=manual: user message does not auto-trigger; manage add speaker triggers one AI" do
    sign_in_as(@admin)

    space = create_group_chat_space!(reply_order: "manual")
    conversation = space.conversations.create!(title: "Manual Smoke", kind: "root")

    visit conversation_url(conversation)

    fill_in "message[content]", with: "Hello manual"
    find("#message_form button[type='submit']", wait: 5).click

    assert_selector "[data-message-role='user']", text: "Hello manual", wait: 10
    assert_no_selector "[data-message-role='assistant']", wait: 2

    names = space.space_memberships.active.ai_characters.by_position.pluck(:cached_display_name)
    expect_next_queue_includes(conversation, names)

    # Open manage modal and add a speaker to start a round.
    open_manage_round_modal

    within "dialog#round_queue_modal" do
      # Ensure frame loads
      assert_selector "turbo-frame#round_queue_editor", wait: 10
      assert_text "No active round", wait: 10

      find("summary", text: "Add speaker", wait: 10).click
      # Click the first available AI member in the dropdown
      first("ul.dropdown-content button", wait: 10).click

      # Now the round should be active (single speaker => no upcoming).
      assert_no_text "No active round", wait: 10
      assert_text "Current", wait: 10
      assert_text "No upcoming speakers in this round.", wait: 10
    end

    drain_conversation_run_jobs!(conversation)
    assert_selector "[data-message-role='assistant']", count: 1, wait: 20

    within "dialog#round_queue_modal" do
      assert_text "No active round", wait: 10
    end
    close_manage_round_modal

    expect_next_queue_includes(conversation, names)
  end

  test "Auto without human: list order runs through both AI in one round" do
    sign_in_as(@admin)

    space = create_group_chat_space!(reply_order: "list")
    conversation = space.conversations.create!(title: "Auto without human Smoke", kind: "root")

    visit conversation_url(conversation)

    # Enable auto without human (UI is single-step: 1 round).
    within "##{dom_id(conversation, :auto_without_human_toggle)}" do
      find("button[data-auto-without-human-toggle-target='button']", wait: 10).click
    end

    within group_queue_selector(conversation) do
      assert_selector ".loading.loading-spinner", wait: 10
      assert_selector ".avatar.tooltip:not(.avatar-placeholder)[data-tip]", count: 1, wait: 10
    end

    open_manage_round_modal
    within "dialog#round_queue_modal" do
      assert_selector "turbo-frame#round_queue_editor", wait: 10
      assert_text "Current", wait: 10
      assert_text "Upcoming", wait: 10
      assert_selector "[data-sortable-item]", count: 1, wait: 10
    end

    drain_conversation_run_jobs!(conversation)
    assert_selector "[data-message-role='assistant']", minimum: 2, wait: 20

    within "dialog#round_queue_modal" do
      assert_text "No active round", wait: 10
    end
    close_manage_round_modal

    names = space.space_memberships.active.ai_characters.by_position.pluck(:cached_display_name)
    expect_next_queue_includes(conversation, names)
  end

  test "Auto (human persona): auto user message is followed by AI response" do
    sign_in_as(@admin)

    space = create_group_chat_space!(reply_order: "list")
    conversation = space.conversations.create!(title: "Auto Smoke", kind: "root")

    visit conversation_url(conversation)

    # Auto user runs require a persona (human-with-persona) for prompt building.
    # Create a dedicated persona character (must be unique within the space).
    persona = characters(:ready_v2).dup
    persona.update!(name: "Admin Persona", file_sha256: SecureRandom.hex(12), visibility: "private")
    space.space_memberships.find_by!(user: @admin, kind: "human").update!(character: persona)

    # Seed some history so Auto (user persona) has context to respond to.
    fill_in "message[content]", with: "Seed history"
    find("#message_form button[type='submit']", wait: 5).click
    assert_selector "[data-message-role='user']", text: "Seed history", wait: 10

    within group_queue_selector(conversation) do
      assert_selector ".loading.loading-spinner", wait: 10
    end

    drain_conversation_run_jobs!(conversation)
    assert_selector "[data-message-role='assistant']", wait: 20

    initial_user_count = all("[data-message-role='user']").size
    initial_assistant_count = all("[data-message-role='assistant']").size

    # Auto toggle is a button labeled "Auto" in the message form.
    within "#message_form" do
      find("button[data-auto-target='autoToggle']", wait: 10).click
    end

    # Toggle is async (fetch); wait for UI to reflect enabled state, then run jobs.
    within "#message_form" do
      assert_selector "button[data-auto-target='autoToggle'].btn-success", wait: 10
    end

    # Wait for TurnScheduler to start the Auto round (server-sourced UI update).
    within group_queue_selector(conversation) do
      assert_selector ".loading.loading-spinner", wait: 10
    end

    open_manage_round_modal
    within "dialog#round_queue_modal" do
      assert_selector "turbo-frame#round_queue_editor", wait: 10
      assert_no_text "No active round", wait: 10
    end

    drain_conversation_run_jobs!(conversation)

    if (failed = conversation.conversation_runs.failed.order(finished_at: :desc).first)
      flunk "Auto run failed: #{failed.error.inspect}"
    end

    # Expect at least one auto-generated user message AND an assistant response after it.
    assert_selector "[data-message-role='user']", count: initial_user_count + 1, wait: 20
    assert_selector "[data-message-role='assistant']", minimum: initial_assistant_count + 1, wait: 20

    within "dialog#round_queue_modal" do
      assert_text "No active round", wait: 10
    end
    close_manage_round_modal
  end
end
