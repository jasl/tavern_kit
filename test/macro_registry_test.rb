# frozen_string_literal: true

require "test_helper"

class MacroRegistryTest < Minitest::Test
  def test_dup_creates_independent_copy
    reg = TavernKit::MacroRegistry.new
    reg.register("a", "1", description: "A")

    copy = reg.dup
    copy.register("b", "2", description: "B")

    assert reg.has?("a")
    refute reg.has?("b")

    assert copy.has?("a")
    assert copy.has?("b")

    assert_equal "A", reg.detect { |m| m.key == :a }&.description
    assert_equal "A", copy.detect { |m| m.key == :a }&.description
  end

  def test_slice_returns_only_requested_keys
    reg = TavernKit::MacroRegistry.new
    reg.register("a", "1")
    reg.register("b", "2")
    reg.register("c", "3")

    sliced = reg.slice("a", :c, "missing")

    assert_equal 2, sliced.size
    assert sliced.has?("a")
    assert sliced.has?(:c)
    refute sliced.has?(:b)
    refute sliced.has?("missing")

    # Original remains unchanged.
    assert_equal 3, reg.size
    assert reg.has?(:b)
  end

  def test_except_removes_requested_keys
    reg = TavernKit::MacroRegistry.new
    reg.register("a", "1")
    reg.register("b", "2")
    reg.register("c", "3")

    filtered = reg.except(:b, "missing")

    assert_equal 2, filtered.size
    refute filtered.has?(:b)
    assert filtered.has?(:a)
    assert filtered.has?(:c)

    # Original remains unchanged.
    assert_equal 3, reg.size
    assert reg.has?(:b)
  end
end
