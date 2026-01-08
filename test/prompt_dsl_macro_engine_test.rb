# frozen_string_literal: true

require "test_helper"

class PromptDslMacroEngineTest < Minitest::Test
  def test_macro_engine_silly_tavern_v1_sets_expander
    dsl = TavernKit::Prompt::DSL.new

    dsl.macro_engine(:silly_tavern_v1)

    assert_instance_of TavernKit::Macro::SillyTavernV1::Engine, dsl.context.expander
  end

  def test_macro_engine_silly_tavern_v2_sets_expander
    dsl = TavernKit::Prompt::DSL.new

    dsl.macro_engine(:silly_tavern_v2)

    assert_instance_of TavernKit::Macro::SillyTavernV2::Engine, dsl.context.expander
  end

  def test_macro_engine_raises_for_unsupported_selector
    dsl = TavernKit::Prompt::DSL.new

    error = assert_raises(ArgumentError) { dsl.macro_engine(:legacy) }
    assert_match(/macro_engine must be :silly_tavern_v1 or :silly_tavern_v2/i, error.message)
  end
end
