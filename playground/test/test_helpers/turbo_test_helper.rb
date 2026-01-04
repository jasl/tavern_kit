# frozen_string_literal: true

# Test helper for Turbo Streams assertions.
#
# Provides methods to assert Turbo Stream broadcasts and renders.
#
module TurboTestHelper
  # Assert that a Turbo Stream broadcast was sent.
  #
  # @param stream_name [String, Array] the stream to check
  # @param count [Integer] expected number of broadcasts
  # @yield the block that should trigger the broadcast
  def assert_turbo_stream_broadcasts(stream_name, count: 1, &block)
    assert_broadcasts(Turbo::StreamsChannel.broadcasting_for(stream_name), count, &block)
  end

  # Assert that no Turbo Stream broadcast was sent.
  #
  # @param stream_name [String, Array] the stream to check
  # @yield the block that should not trigger a broadcast
  def assert_no_turbo_stream_broadcasts(stream_name, &block)
    assert_no_broadcasts(Turbo::StreamsChannel.broadcasting_for(stream_name), &block)
  end

  # Assert Turbo Stream response contains expected action.
  #
  # @param action [String] expected action (append, prepend, replace, remove, etc.)
  # @param target [String, nil] expected target ID
  def assert_turbo_stream(action:, target: nil)
    assert_response :success
    assert_match %r{<turbo-stream action="#{action}"}, response.body
    assert_match %r{target="#{target}"}, response.body if target
  end
end
