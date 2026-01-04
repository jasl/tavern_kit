# frozen_string_literal: true

require "test_helper"

class TokenEstimatorTest < Minitest::Test
  def test_default_caches_per_encoding
    a = TavernKit::TokenEstimator.default(encoding: "cl100k_base")
    b = TavernKit::TokenEstimator.default(encoding: "r50k_base")

    refute_same a, b
    assert_equal "cl100k_base", a.encoding_name
    assert_equal "r50k_base", b.encoding_name
  end

  def test_default_normalizes_cache_key
    a = TavernKit::TokenEstimator.default(model: nil, encoding: "cl100k_base")
    b = TavernKit::TokenEstimator.default(model: "  ", encoding: "  cl100k_base ")

    assert_same a, b
  end
end
