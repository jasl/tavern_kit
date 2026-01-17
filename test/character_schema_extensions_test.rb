# frozen_string_literal: true

require "test_helper"

class CharacterSchemaExtensionsTest < Minitest::Test
  def test_talkativeness_predicate_is_key_based
    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [])
    refute schema.talkativeness?

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { talkativeness: nil })
    assert schema.talkativeness?
  end

  def test_talkativeness_factor_uses_st_semantics
    default = 0.5

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [])
    assert_in_delta default, schema.talkativeness_factor(default: default), 0.0001

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { talkativeness: nil })
    assert_in_delta 0.0, schema.talkativeness_factor(default: default), 0.0001

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { talkativeness: "" })
    assert_in_delta 0.0, schema.talkativeness_factor(default: default), 0.0001

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { talkativeness: "0.7" })
    assert_in_delta 0.7, schema.talkativeness_factor(default: default), 0.0001

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { talkativeness: "abc" })
    assert_in_delta default, schema.talkativeness_factor(default: default), 0.0001

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { talkativeness: true })
    assert_in_delta 1.0, schema.talkativeness_factor(default: default), 0.0001
  end

  def test_extension_value_preserves_false_for_string_keys
    schema =
      TavernKit::Character::Schema.new(
        name: "A",
        group_only_greetings: [],
        extensions: { "some_flag" => false }
      )

    assert_equal false, schema.send(:extension_value, :some_flag)
  end

  def test_extension_value_does_not_fall_through_when_string_key_exists_with_nil
    schema =
      TavernKit::Character::Schema.new(
        name: "A",
        group_only_greetings: [],
        extensions: { "talkativeness" => nil, talkativeness: 0.9 }
      )

    assert_nil schema.send(:extension_value, :talkativeness)
  end

  def test_world_name_is_blank_safe
    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [])
    assert_nil schema.world_name

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { world: "" })
    assert_nil schema.world_name

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { world: "  My World  " })
    assert_equal "My World", schema.world_name
  end

  def test_extra_world_names_is_array_only_and_strips
    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [])
    assert_equal [], schema.extra_world_names

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { extra_worlds: "not an array" })
    assert_equal [], schema.extra_world_names

    schema =
      TavernKit::Character::Schema.new(
        name: "A",
        group_only_greetings: [],
        extensions: { extra_worlds: ["  One  ", "", nil, "Two"] }
      )
    assert_equal ["One", "Two"], schema.extra_world_names
  end
end
