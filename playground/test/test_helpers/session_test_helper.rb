# frozen_string_literal: true

# Test helper for session/authentication in integration tests.
#
# Provides methods to sign in users for controller tests.
#
# @example Sign in a user
#   sign_in :admin
#   sign_in users(:member)
#
module SessionTestHelper
  # Sign in a user for testing.
  #
  # Signs out any existing session first to ensure clean state.
  #
  # @param user [Symbol, User] user fixture name or User instance
  # @return [void]
  def sign_in(user)
    user = users(user) unless user.is_a?(User)

    # Sign out existing session if any
    delete session_url if cookies[:session_token].present?

    post session_url, params: { email: user.email, password: "password123" }

    # Verify sign-in succeeded
    assert_response :redirect, "Sign in failed for #{user.email}"
    follow_redirect!
  end

  # Sign out the current user.
  #
  # @return [void]
  def sign_out
    delete session_url
  end

  # Check if a user is signed in.
  #
  # @return [Boolean]
  def signed_in?
    cookies[:session_token].present?
  end
end
