# frozen_string_literal: true

require "test_helper"

class PlaygroundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin
  end

  test "index renders the playgrounds list page" do
    get playgrounds_url
    assert_response :success
    assert_select "h1", text: /Chats/i
  end

  test "index shows empty state when user has no playgrounds" do
    # Use status: "removed" to simulate user leaving the space
    space_memberships(:admin_in_general).update!(status: "removed")
    space_memberships(:admin_in_archived).update!(status: "removed")

    get playgrounds_url
    assert_response :success
    assert_select "h3", text: /No chats yet/i
  end

  test "show renders the playground page and records the last space visited in a cookie" do
    playground = spaces(:general)

    get playground_url(playground)
    assert_response :success
    assert_equal playground.id.to_s, cookies[:last_space]
    assert_select "h1", text: playground.name
  end

  test "show redirects to root for inaccessible playground" do
    other_user = users(:member)
    other_playground = Spaces::Playground.create!(name: "Secret Playground", owner: other_user)
    other_playground.space_memberships.create!(kind: "human", user: other_user, role: "owner", position: 0)

    get playground_url(other_playground)
    assert_redirected_to root_url
  end

  test "new displays form for creating a playground" do
    get new_playground_url
    assert_response :success
  end

  test "create creates a playground and an owner membership" do
    assert_difference "Spaces::Playground.count", 1 do
      assert_difference "SpaceMembership.count", 1 do
        post playgrounds_url, params: { playground: { name: "New Playground" } }
      end
    end

    playground = Spaces::Playground.order(:created_at, :id).last
    assert_equal users(:admin), playground.owner
    assert playground.playground?

    owner_membership = playground.space_memberships.find_by(user: users(:admin), kind: "human")
    assert owner_membership
    assert_equal "owner", owner_membership.role

    assert_redirected_to playground_url(playground)
  end

  test "create persists TavernKit preset settings under settings.preset" do
    post playgrounds_url, params: {
      playground: {
        name: "Preset Playground",
        settings: {
          preset: {
            main_prompt: "CUSTOM MAIN PROMPT",
            post_history_instructions: "CUSTOM PHI",
            authors_note: "CUSTOM AN",
            authors_note_frequency: 2,
            authors_note_position: "before_prompt",
            authors_note_depth: 7,
            message_token_overhead: 12,
          },
        },
      },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    assert_equal "CUSTOM MAIN PROMPT", playground.settings.dig("preset", "main_prompt")
    assert_equal "CUSTOM PHI", playground.settings.dig("preset", "post_history_instructions")
    assert_equal "CUSTOM AN", playground.settings.dig("preset", "authors_note")
    assert_equal 2, playground.settings.dig("preset", "authors_note_frequency")
    assert_equal "before_prompt", playground.settings.dig("preset", "authors_note_position")
    assert_equal 7, playground.settings.dig("preset", "authors_note_depth")
    assert_equal 12, playground.settings.dig("preset", "message_token_overhead")
  end
end
