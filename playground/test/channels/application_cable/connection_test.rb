# frozen_string_literal: true

require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with valid session cookie" do
    user = users(:admin)
    session = sessions(:admin_session)

    # Simulate the session cookie
    cookies.signed[:session_token] = session.token

    connect

    assert_equal user, connection.current_user
  end

  test "rejects connection without session cookie" do
    assert_reject_connection { connect }
  end

  test "rejects connection with invalid session token" do
    cookies.signed[:session_token] = "invalid_token"

    assert_reject_connection { connect }
  end

  test "rejects connection with expired session" do
    session = sessions(:admin_session)
    # Make the session appear deleted by destroying it
    session.destroy!

    cookies.signed[:session_token] = session.token

    assert_reject_connection { connect }
  end
end
