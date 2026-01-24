# frozen_string_literal: true

require "test_helper"

class Translation::MaskerTest < ActiveSupport::TestCase
  test "masks and unmasks protected segments" do
    masking = ConversationSettings::I18nMaskingSettings.new({})
    masker = Translation::Masker.new(masking: masking)

    text = <<~TEXT.strip
      Hello {{user}}!
      ```ruby
      puts "hi"
      ```
      Visit https://example.com/foo
      Inline `code` here.
    TEXT

    masked = masker.mask(text)
    assert masked.tokens.any?
    assert_equal masked.tokens.length, masked.replacements.length

    masked.tokens.each do |token|
      assert_includes masked.text, token
      refute_includes masked.text, masked.replacements.fetch(token)
    end

    restored = masker.unmask(masked.text, replacements: masked.replacements)
    assert_equal text, restored
  end

  test "validates token preservation" do
    masking = ConversationSettings::I18nMaskingSettings.new({})
    masker = Translation::Masker.new(masking: masking)

    masked = masker.mask("Hello {{user}}")
    token = masked.tokens.first
    assert token

    assert_raises(Translation::MaskMismatchError) do
      masker.validate_tokens!("Hello", tokens: [token])
    end
  end
end
