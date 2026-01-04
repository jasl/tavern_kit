# frozen_string_literal: true

require "test_helper"

class ExampleParserTest < Minitest::Test
  def test_parse_blocks_with_start_and_multiline_messages
    text = <<~EX
      <START>
      {{user}}: Hello
      {{char}}: Hi!
      <START>
      {{user}}: Multi
      line
      {{char}}: Reply
      and more
    EX

    blocks = TavernKit::Prompt::ExampleParser.parse_blocks(text)

    assert_equal 2, blocks.length

    b0 = blocks[0]
    assert_equal 2, b0.length
    assert_equal :user, b0[0].role
    assert_equal "Hello", b0[0].content
    assert_equal :assistant, b0[1].role
    assert_equal "Hi!", b0[1].content

    b1 = blocks[1]
    assert_equal 2, b1.length
    assert_equal :user, b1[0].role
    assert_equal "Multi\nline", b1[0].content
    assert_equal :assistant, b1[1].role
    assert_equal "Reply\nand more", b1[1].content
  end
end
