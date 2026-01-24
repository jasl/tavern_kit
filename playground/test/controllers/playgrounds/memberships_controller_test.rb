# frozen_string_literal: true

require "test_helper"

class Playgrounds::MembershipsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin
    @playground = spaces(:general)
  end

  test "create adds an AI character membership to the playground" do
    character = characters(:ready_v3)

    assert_difference "SpaceMembership.count", 1 do
      post playground_memberships_url(@playground), params: { character_ids: [character.id] }
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

    patch playground_membership_url(@playground, membership), params: { space_membership: { participation: "muted" } }
    assert_redirected_to playground_url(@playground)
    assert membership.reload.participation_muted?
  end

  test "update can set a membership name override" do
    membership = space_memberships(:character_in_general)

    patch playground_membership_url(@playground, membership), params: { space_membership: { name_override: "New Name" } }

    assert_redirected_to playground_url(@playground)
    assert_equal "New Name", membership.reload.name_override
    assert_equal "New Name", membership.display_name
  end

  test "update redirects when return_to is present for turbo stream requests" do
    membership = space_memberships(:character_in_general)
    conversation = @playground.conversations.root.first

    patch playground_membership_url(@playground, membership),
          params: { space_membership: { persona: "New persona" }, return_to: conversation_path(conversation) },
          as: :turbo_stream

    assert_redirected_to conversation_url(conversation)
    assert_equal "New persona", membership.reload.persona
  end

  test "destroy removes a character membership" do
    membership = space_memberships(:character_in_general)

    delete playground_membership_url(@playground, membership)
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

  test "enabling auto disables auto without human" do
    playground = Spaces::Playground.create!(name: "Auto Disables Auto without human", owner: users(:admin), reply_order: "list")
    playground.space_memberships.grant_to(users(:admin), role: "owner")
    playground.space_memberships.grant_to(characters(:ready_v2))
    playground.space_memberships.grant_to(characters(:ready_v3))

    conversation = playground.conversations.create!(title: "Main", kind: "root")
    conversation.start_auto_without_human!(rounds: 2)
    assert conversation.auto_without_human_enabled?

    persona =
      Character.create!(
        name: "Auto Persona",
        personality: "Test",
        data: { "name" => "Auto Persona" },
        spec_version: 2,
        file_sha256: "auto_persona_#{SecureRandom.hex(8)}",
        status: "ready",
        visibility: "private"
      )

    membership = playground.space_memberships.find_by!(user: users(:admin), kind: "human")

    TurnScheduler.stubs(:stop!)
    TurnScheduler.stubs(:start_round!).returns(true)

    patch playground_membership_url(playground, membership),
          params: { space_membership: { character_id: persona.id, auto: "auto" } },
          as: :json

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal true, body["auto_without_human_disabled"]

    assert_not conversation.reload.auto_without_human_enabled?
    assert membership.reload.auto_enabled?
  end
end
