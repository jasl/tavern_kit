# frozen_string_literal: true

require "test_helper"

class Conversations::ExporterTest < ActiveSupport::TestCase
  fixtures :users, :characters, :llm_providers

  setup do
    # Export should be independent of scheduler behavior.
    Message.any_instance.stubs(:notify_scheduler_turn_complete)

    @space = Spaces::Playground.create!(name: "Export Space", owner: users(:admin), reply_order: "manual")
    @user_membership = @space.space_memberships.create!(kind: "human", role: "owner", user: users(:admin))
    @character_membership = @space.space_memberships.create!(
      kind: "character",
      role: "member",
      character: characters(:ready_v2),
      llm_provider: llm_providers(:openai)
    )
    @conversation = @space.conversations.create!(title: "Export", kind: "root")
  end

  test "to_jsonl exports normal+excluded and omits hidden" do
    normal = @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello JSONL")
    excluded = @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Excluded JSONL",
      visibility: "excluded"
    )
    hidden = @conversation.messages.create!(
      space_membership: @character_membership,
      role: "assistant",
      content: "HIDDEN JSONL",
      visibility: "hidden"
    )

    jsonl = Conversations::Exporter.to_jsonl(@conversation)
    lines = jsonl.split("\n")

    assert_equal 3, lines.size

    header = JSON.parse(lines[0])
    assert_equal @conversation.id, header.dig("conversation", "id")

    messages = lines.drop(1).map { |line| JSON.parse(line) }
    ids = messages.map { |m| m["id"] }

    assert_includes ids, normal.id
    assert_includes ids, excluded.id
    refute_includes ids, hidden.id

    exported_normal = messages.find { |m| m["id"] == normal.id }
    exported_excluded = messages.find { |m| m["id"] == excluded.id }

    assert_equal "normal", exported_normal["visibility"]
    assert_equal false, exported_normal["excluded_from_prompt"]

    assert_equal "excluded", exported_excluded["visibility"]
    assert_equal true, exported_excluded["excluded_from_prompt"]
  end

  test "to_txt includes excluded marker and omits hidden" do
    @conversation.messages.create!(space_membership: @user_membership, role: "user", content: "Hello TXT")
    @conversation.messages.create!(
      space_membership: @user_membership,
      role: "user",
      content: "Excluded TXT",
      visibility: "excluded"
    )
    @conversation.messages.create!(
      space_membership: @character_membership,
      role: "assistant",
      content: "HIDDEN TXT",
      visibility: "hidden"
    )

    txt = Conversations::Exporter.to_txt(@conversation)

    assert_includes txt, "Hello TXT"
    assert_includes txt, "Excluded TXT"
    assert_includes txt, "[EXCLUDED]"
    refute_includes txt, "HIDDEN TXT"
  end
end
