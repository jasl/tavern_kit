# frozen_string_literal: true

require "test_helper"

class SpaceLorebooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :member

    @victim_playground = spaces(:general) # owned by admin
    @victim_lorebook = Lorebook.create!(name: "Victim Lorebook")
  end

  test "index redirects for playgrounds outside current user's spaces" do
    get playground_space_lorebooks_url(@victim_playground)

    assert_redirected_to root_url
  end

  test "create does not attach lorebooks for playgrounds outside current user's spaces" do
    assert_no_difference "SpaceLorebook.count" do
      post playground_space_lorebooks_url(@victim_playground), params: {
        space_lorebook: {
          lorebook_id: @victim_lorebook.id,
          source: "global",
          enabled: true,
        },
      }
    end

    assert_redirected_to root_url
  end

  test "destroy does not detach lorebooks for playgrounds outside current user's spaces" do
    victim_attachment =
      SpaceLorebook.create!(
        space: @victim_playground,
        lorebook: @victim_lorebook,
        source: "global",
        enabled: true
      )

    assert_no_difference "SpaceLorebook.count" do
      delete playground_space_lorebook_url(@victim_playground, victim_attachment)
    end

    assert_redirected_to root_url
    assert SpaceLorebook.exists?(victim_attachment.id)
  end

  test "toggle does not modify attachments for playgrounds outside current user's spaces" do
    victim_attachment =
      SpaceLorebook.create!(
        space: @victim_playground,
        lorebook: @victim_lorebook,
        source: "global",
        enabled: true
      )

    patch toggle_playground_space_lorebook_url(@victim_playground, victim_attachment)

    assert_redirected_to root_url

    victim_attachment.reload
    assert_equal true, victim_attachment.enabled
  end
end
