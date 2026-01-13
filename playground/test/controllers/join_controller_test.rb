# frozen_string_literal: true

require "test_helper"

class JoinControllerTest < ActionDispatch::IntegrationTest
  setup do
    @invite_code = InviteCode.generate!(created_by: users(:admin), note: "Test invite")
  end

  test "show redirects signed-in users to root" do
    sign_in :member

    get join_url(@invite_code.code)

    assert_redirected_to root_url
  end

  test "create registers user and starts session" do
    assert_difference "Session.count", 1 do
      assert_difference "User.count", 1 do
        post join_url(@invite_code.code), params: {
          user: {
            name: "New User",
            email: "new_user_#{SecureRandom.hex(4)}@example.com",
            password: "password123",
          },
        }
      end
    end

    assert_redirected_to root_url
    assert cookies[:session_token].present?
  end
end
