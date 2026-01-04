# frozen_string_literal: true

require "test_helper"

class PortraitRoutesTest < ActionDispatch::IntegrationTest
  test "fresh_space_membership_portrait_path uses signed id" do
    membership = space_memberships(:admin_in_general)
    membership.define_singleton_method(:portrait_token) { raise "should not be called" }

    signed_id = membership.signed_id(purpose: :portrait)

    path = fresh_space_membership_portrait_path(membership)

    assert_includes path, signed_id
    assert_includes path, membership.updated_at.to_fs(:number)
  end

  test "fresh_character_portrait_path uses signed id" do
    character = characters(:ready_v2)
    character.define_singleton_method(:portrait_token) { raise "should not be called" }

    signed_id = character.signed_id(purpose: :portrait)

    path = fresh_character_portrait_path(character)

    assert_includes path, signed_id
    assert_includes path, character.updated_at.to_fs(:number)
  end
end
