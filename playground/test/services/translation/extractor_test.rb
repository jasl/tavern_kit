# frozen_string_literal: true

require "test_helper"

class Translation::ExtractorTest < ActiveSupport::TestCase
  test "extracts textarea content" do
    raw = "<textarea>Hello\nworld</textarea>"
    assert_equal "Hello\nworld", Translation::Extractor.extract!(raw)
  end

  test "extracts fenced code block content" do
    raw = "```text\nHello\nworld\n```"
    assert_equal "Hello\nworld\n", Translation::Extractor.extract!(raw)
  end

  test "falls back to raw content when wrapper is missing" do
    raw = "Hello world"
    assert_equal raw, Translation::Extractor.extract!(raw)
  end

  test "raises when textarea wrapper is malformed" do
    assert_raises(Translation::ExtractionError) do
      Translation::Extractor.extract!("<textarea>Hello")
    end
  end

  test "raises when fenced code block wrapper is malformed" do
    assert_raises(Translation::ExtractionError) do
      Translation::Extractor.extract!("```Hello")
    end
  end
end
