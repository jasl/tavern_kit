# frozen_string_literal: true

require "test_helper"

require "json"
require "open3"
require "rbconfig"

class CliPromptTest < Minitest::Test
  def setup
    @repo_root = File.expand_path("..", __dir__)
    @exe_path = File.expand_path("../exe/tavern_kit", __dir__)
    @fixture_v2_min = File.expand_path("fixtures/seraphina.v2.json", __dir__)
    @fixture_v2_full = File.expand_path("fixtures/full_v2_card.json", __dir__)
  end

  def run_cli(*args)
    Open3.capture3(RbConfig.ruby, @exe_path, *args, chdir: @repo_root)
  end

  def test_prompt_requires_user
    _stdout, stderr, status = run_cli("prompt", "--card", @fixture_v2_full, "--message", "hi")

    assert_equal 2, status.exitstatus
    assert_match(/ERROR: --user is required\./, stderr)
    assert_match(/Usage:/, stderr)
  end

  def test_prompt_requires_message
    _stdout, stderr, status = run_cli("prompt", "--card", @fixture_v2_full, "--user", "User")

    assert_equal 2, status.exitstatus
    assert_match(/ERROR: --message is required\./, stderr)
    assert_match(/Usage:/, stderr)
  end

  def test_prompt_rejects_empty_message
    _stdout, stderr, status = run_cli("prompt", "--card", @fixture_v2_full, "--user", "User", "--message", "")

    assert_equal 2, status.exitstatus
    assert_match(/ERROR: --message is required\./, stderr)
    assert_match(/Usage:/, stderr)
  end

  def test_prompt_handles_out_of_range_greeting_without_stack_trace
    _stdout, stderr, status = run_cli(
      "prompt",
      "--card", @fixture_v2_min,
      "--user", "User",
      "--message", "hi",
      "--greeting", "1"
    )

    assert_equal 2, status.exitstatus
    assert_match(/ERROR: Greeting index 1 out of range/, stderr)
    refute_match(/:in `/, stderr)
    refute_match(/Usage:/, stderr)
  end

  def test_prompt_outputs_openai_messages_json
    stdout, stderr, status = run_cli(
      "prompt",
      "--card", @fixture_v2_full,
      "--user", "User",
      "--message", "hello"
    )

    assert status.success?, stderr
    assert_equal "", stderr

    messages = JSON.parse(stdout)
    assert_kind_of Array, messages
    refute_empty messages
    assert_kind_of Hash, messages.first
    assert messages.first.key?("role")
    assert messages.first.key?("content")
  end

  def test_prompt_outputs_openai_messages_json_with_dialect_openai
    stdout, stderr, status = run_cli(
      "prompt",
      "--card", @fixture_v2_full,
      "--user", "User",
      "--message", "hello",
      "--dialect", "openai"
    )

    assert status.success?, stderr
    assert_equal "", stderr

    messages = JSON.parse(stdout)
    assert_kind_of Array, messages
    refute_empty messages
    assert_kind_of Hash, messages.first
    assert messages.first.key?("role")
    assert messages.first.key?("content")
  end

  def test_prompt_outputs_anthropic_messages_json_with_dialect_anthropic
    stdout, stderr, status = run_cli(
      "prompt",
      "--card", @fixture_v2_full,
      "--user", "User",
      "--message", "hello",
      "--dialect", "anthropic"
    )

    assert status.success?, stderr
    assert_equal "", stderr

    result = JSON.parse(stdout)
    assert_kind_of Hash, result
    assert result.key?("messages")
    assert result.key?("system")

    messages = result["messages"]
    assert_kind_of Array, messages
    refute_empty messages
    assert_kind_of Hash, messages.first
    assert messages.first.key?("role")
    assert messages.first.key?("content")

    content = messages.first["content"]
    assert_kind_of Array, content
    refute_empty content
    assert_kind_of Hash, content.first
    assert content.first.key?("type")
    assert content.first.key?("text")

    system = result["system"]
    assert_kind_of Array, system
  end

  def test_prompt_outputs_text_completion_with_dialect_text
    stdout, stderr, status = run_cli(
      "prompt",
      "--card", @fixture_v2_full,
      "--user", "User",
      "--message", "hello",
      "--dialect", "text"
    )

    assert status.success?, stderr
    assert_equal "", stderr

    assert_includes stdout, "System:"
    assert stdout.end_with?("assistant:\n"), "Expected output to end with assistant:, got: #{stdout.inspect}"
  end

  def test_prompt_rejects_unknown_dialect_with_usage
    _stdout, stderr, status = run_cli(
      "prompt",
      "--card", @fixture_v2_full,
      "--user", "User",
      "--message", "hello",
      "--dialect", "wat"
    )

    assert_equal 2, status.exitstatus
    supported = TavernKit::Prompt::Dialects::SUPPORTED.join("|")
    assert_match(/ERROR: --dialect must be one of #{Regexp.escape(supported)}, got "wat"/, stderr)
    assert_match(/Usage:/, stderr)
  end
end
