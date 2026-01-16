# frozen_string_literal: true

require "application_system_test_case"

class ConversationRightSidebarTest < ApplicationSystemTestCase
  setup do
    @admin = users(:admin)
    @mock_provider = llm_providers(:mock_local)

    Preset.seed_system_presets!
  end

  # Sign in via the login form
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

    @mock_provider.update!(base_url: "#{base}/mock_llm/v1", model: "mock", streamable: true)
    LLMProvider.set_default!(@mock_provider)
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

  test "right sidebar: preset switch updates UI, autosave persists, invalid number input does not wipe settings" do
    sign_in_as(@admin)

    space = Spaces::Playground.create!(
      name: "Sidebar Test Space",
      owner: @admin,
      reply_order: "natural"
    )
    space.space_memberships.grant_to(@admin, role: "owner")
    space.space_memberships.grant_to(characters(:ready_v2))

    ai_membership = space.space_memberships.active.ai_characters.first
    ai_membership.update!(llm_provider: @mock_provider)

    precise = Preset.system_presets.find_by!(name: "Precise")
    creative = Preset.system_presets.find_by!(name: "Creative")
    precise.apply_to(ai_membership)

    conversation = space.conversations.create!(title: "Sidebar Conversation", kind: "root")

    visit conversation_url(conversation)

    temp_selector = "input[type='number'][data-setting-path='settings.llm.providers.openai_compatible.generation.temperature']"
    top_p_selector = "input[type='number'][data-setting-path='settings.llm.providers.openai_compatible.generation.top_p']"
    provider_select = "select[data-setting-path='llm_provider_id']"

    # Wait for schema-rendered fields to appear (Turbo + Stimulus + schema fetch)
    assert_selector temp_selector, wait: 10
    assert_selector top_p_selector, wait: 10

    assert_equal "0.7", find(temp_selector).value
    assert_equal "0.9", find(top_p_selector).value

    # Apply "Creative" preset via the dropdown (Turbo Stream replaces the sidebar)
    within "#llm_settings_panel" do
      find("[data-preset-selector-target='dropdown'] [role='button']", wait: 5).click
      find("a[data-preset-id='#{creative.id}']", wait: 5).click
    end

    wait_for(timeout: 10) do
      page.has_selector?(temp_selector, wait: 0) &&
        find(temp_selector).value == "1.3" &&
        find(top_p_selector).value == "0.95"
    end

    ai_membership.reload
    assert_in_delta 1.3, ai_membership.settings.llm.providers.openai_compatible.generation.temperature, 0.0001
    assert_in_delta 0.95, ai_membership.settings.llm.providers.openai_compatible.generation.top_p, 0.0001

    # Autosave: edit temperature via the numeric input and verify it persists to DB
    find(temp_selector).set("0.8")

    wait_for(timeout: 10) do
      ai_membership.reload
      ai_membership.settings.llm.providers.openai_compatible.generation.temperature.round(2) == 0.8
    end

    # Invalid number input should not overwrite the saved value.
    # In browsers, typing non-numeric chars into <input type="number"> often results in value=""
    # and a "badInput" validity state. Simulate that path without relying on driver-specific
    # behavior for `set("")` (which can be normalized to "0" under min=0 constraints).
    execute_script(<<~JS, temp_selector)
      const el = document.querySelector(arguments[0])
      el.focus()
      el.value = "not-a-number"
      el.dispatchEvent(new Event("input", { bubbles: true }))
      el.blur()
    JS

    sleep 1
    ai_membership.reload
    assert_equal 0.8, ai_membership.settings.llm.providers.openai_compatible.generation.temperature.round(2)

    # Ensure selecting "Use Global Provider" (value="") is still savable (null transition allowed for <select>).
    find(provider_select).find("option[value='']").select_option

    wait_for(timeout: 10) do
      ai_membership.reload
      ai_membership.llm_provider_id.nil?
    end
  end
end
