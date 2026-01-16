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

  def test_fav_coercion
    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [])
    refute schema.fav?

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { fav: true })
    assert schema.fav?

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { fav: "true" })
    assert schema.fav?

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { fav: "false" })
    refute schema.fav?

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { fav: 1 })
    assert schema.fav?

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { fav: 0 })
    refute schema.fav?
  end

  def test_world_name_is_blank_safe
    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [])
    assert_nil schema.world_name

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { world: "" })
    assert_nil schema.world_name

    schema = TavernKit::Character::Schema.new(name: "A", group_only_greetings: [], extensions: { world: "  My World  " })
    assert_equal "My World", schema.world_name
  end
end

