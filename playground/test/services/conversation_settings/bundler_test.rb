# frozen_string_literal: true

require "test_helper"

class ConversationSettings::BundlerTest < ActiveSupport::TestCase
  test "bundle removes external $ref (keeps internal or inlines)" do
    schema = ConversationSettings::SchemaBundle.schema

    refs = collect_ref_values(schema)
    assert refs.all? { |r| r.start_with?("#") }, "Expected only internal refs, got: #{refs.uniq.sort.take(5).inspect}"
  end

  test "bundle uses ECMA-262 anchors for version pattern" do
    schema = ConversationSettings::SchemaBundle.schema

    version_pattern = schema.dig("properties", "version", "pattern")
    assert version_pattern.is_a?(String), "Expected version pattern to be a String, got: #{version_pattern.inspect}"

    assert version_pattern.start_with?("^"), "Expected pattern to start with ^, got: #{version_pattern.inspect}"
    assert version_pattern.end_with?("$"), "Expected pattern to end with $, got: #{version_pattern.inspect}"

    # Ruby-only anchors must not leak into the JSON Schema export.
    refute_includes version_pattern, "\\A"
    refute_includes version_pattern, "\\z"
    refute_includes version_pattern, "\\Z"
  end

  test "bundle includes participant openai max_context_tokens schema and preserves x-ui" do
    schema = ConversationSettings::SchemaBundle.schema

    max_context_tokens_schema =
      schema.dig(
        "properties", "participant",
        "properties", "llm",
        "properties", "providers",
        "properties", "openai",
        "properties", "generation",
        "properties", "max_context_tokens"
      )

    assert max_context_tokens_schema, "Expected schema under participant.llm.providers.openai.generation.max_context_tokens"
    assert max_context_tokens_schema.dig("x-ui", "control"), "Expected schema to preserve x-ui"
  end

  test "bundle preserves visibleWhen for provider gating" do
    schema = ConversationSettings::SchemaBundle.schema

    visible_when =
      schema.dig(
        "properties", "participant",
        "properties", "llm",
        "properties", "providers",
        "properties", "openai",
        "x-ui", "visibleWhen"
      )

    assert_equal({ "context" => "provider_identification", "const" => "openai" }, visible_when)
  end

  private

  def collect_ref_values(node, refs = [])
    case node
    when Hash
      refs << node["$ref"] if node["$ref"].is_a?(String)
      node.each_value { |v| collect_ref_values(v, refs) }
    when Array
      node.each { |v| collect_ref_values(v, refs) }
    end

    refs
  end
end
