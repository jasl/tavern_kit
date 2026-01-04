# frozen_string_literal: true

require "test_helper"

class SpaceMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin
    @playground = spaces(:general)
  end

  test "create adds an AI character membership to the playground" do
    character = characters(:ready_v3)

    assert_difference "SpaceMembership.count", 1 do
      post playground_space_memberships_url(@playground), params: { space_membership: { character_id: character.id } }
    end

    membership = SpaceMembership.order(:created_at, :id).last
    assert_equal @playground, membership.space
    assert_equal "character", membership.kind
    assert_equal character, membership.character
    # Redirects to conversation if exists, otherwise playground
    conversation = @playground.conversations.root.first
    if conversation
      assert_redirected_to conversation_url(conversation)
    else
      assert_redirected_to playground_url(@playground)
    end
  end

  test "update can mute a character membership" do
    membership = space_memberships(:character_in_general)

    patch playground_space_membership_url(@playground, membership), params: { space_membership: { participation: "muted" } }
    assert_redirected_to playground_url(@playground)
    assert membership.reload.participation_muted?
  end

  test "destroy removes a character membership" do
    membership = space_memberships(:character_in_general)

    delete playground_space_membership_url(@playground, membership)
    # Redirects to conversation if exists, otherwise playground
    conversation = @playground.conversations.root.first
    if conversation
      assert_redirected_to conversation_url(conversation)
    else
      assert_redirected_to playground_url(@playground)
    end
    membership.reload
    assert membership.removed_membership?, "Expected membership to be removed"
    assert membership.participation_muted?, "Expected participation to be muted"
    assert_not_nil membership.removed_at
  end
end
