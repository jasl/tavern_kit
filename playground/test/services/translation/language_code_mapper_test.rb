# frozen_string_literal: true

require "test_helper"

class Translation::LanguageCodeMapperTest < ActiveSupport::TestCase
  test "maps zh-CN/zh-TW for Microsoft/Bing" do
    assert_equal "zh-Hans", Translation::LanguageCodeMapper.map("bing", "zh-CN")
    assert_equal "zh-Hant", Translation::LanguageCodeMapper.map("microsoft", "zh-TW")
  end

  test "returns original for llm" do
    assert_equal "zh-CN", Translation::LanguageCodeMapper.map("llm", "zh-CN")
  end

  test "handles blank lang codes" do
    assert_equal "", Translation::LanguageCodeMapper.map("bing", "")
    assert_equal "", Translation::LanguageCodeMapper.map("bing", nil)
  end
end
