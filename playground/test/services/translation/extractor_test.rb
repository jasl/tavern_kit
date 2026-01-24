# frozen_string_literal: true

require "test_helper"

class Translation::ExtractorTest < ActiveSupport::TestCase
  test "extracts textarea content" do
    raw = "<textarea>Hello\nworld</textarea>"
    assert_equal "Hello\nworld", Translation::Extractor.extract!(raw)
  end

  test "raises when textarea is missing" do
    assert_raises(Translation::ExtractionError) do
      Translation::Extractor.extract!("no textarea here")
    end
  end
end
