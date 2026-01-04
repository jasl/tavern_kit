# frozen_string_literal: true

require "test_helper"

class MacroPipelineTest < Minitest::Test
  def test_initializer_fails_fast_on_non_enumerable_registry
    assert_raises(ArgumentError) do
      TavernKit::Macro::Pipeline.new(Object.new)
    end
  end

  def test_nil_registry_behaves_as_empty_pipeline
    pipeline = TavernKit::Macro::Pipeline.new(nil)
    assert_equal "hello", pipeline.apply("hello")
  end
end
