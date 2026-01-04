# frozen_string_literal: true

require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "get caches missing values (nil) to avoid repeated database queries" do
    store = ActiveSupport::Cache::MemoryStore.new
    missing_key = "missing.#{SecureRandom.hex(8)}"

    Rails.stubs(:cache).returns(store)

    # The key doesn't exist in fixtures; it should query once, then use cached nil.
    Setting.expects(:find_by).with(key: missing_key).returns(nil).once

    assert_equal "{}", Setting.get(missing_key, "{}")
    assert_equal "{}", Setting.get(missing_key, "{}")
  end
end
