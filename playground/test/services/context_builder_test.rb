# frozen_string_literal: true

require "test_helper"

class ContextBuilderTest < ActiveSupport::TestCase
  def message_contents(messages)
    messages.map { |m| m.fetch(:content) }.join("\n")
  end

  test "card handling swap vs join" do
    user = users(:admin)

    character_a =
      Character.create!(
        name: "Alpha",
        status: "ready",
        spec_version: 2,
        data: {
          "name" => "Alpha",
          "description" => "Alpha desc",
          "scenario" => "Alpha scenario",
        }
      )

    character_b =
      Character.create!(
        name: "Beta",
        status: "ready",
        spec_version: 2,
        data: {
          "name" => "Beta",
          "description" => "Beta desc",
        }
      )

    space =
      Spaces::Playground.create!(
        name: "Context Space",
        owner: user,
        settings: {
          "join_prefix" => "<fieldname>:{{char}}:",
          "join_suffix" => "",
        }
      )

    space.space_memberships.create!(kind: "human", user: user, role: "owner", position: 0)
    speaker = space.space_memberships.create!(kind: "character", character: character_a, role: "member", position: 1)
    space.space_memberships.create!(kind: "character", character: character_b, role: "member", position: 2)

    conversation = space.conversations.create!(title: "Main")

    swap = ContextBuilder.new(conversation, speaker: speaker).build(card_mode: "swap")
    swap_text = message_contents(swap)
    assert_includes swap_text, "Alpha desc"
    assert_not_includes swap_text, "Beta desc"

    joined = ContextBuilder.new(conversation, speaker: speaker).build(card_mode: "join_include_non_participating")
    joined_text = message_contents(joined)
    assert_includes joined_text, "Alpha desc"
    assert_includes joined_text, "Beta desc"
  end

  test "join_exclude_non_participating excludes non-participating members unless speaker" do
    user = users(:admin)

    character_a =
      Character.create!(
        name: "Alpha",
        status: "ready",
        spec_version: 2,
        data: { "name" => "Alpha", "description" => "Alpha desc" }
      )

    character_b =
      Character.create!(
        name: "Beta",
        status: "ready",
        spec_version: 2,
        data: { "name" => "Beta", "description" => "Beta desc" }
      )

    space =
      Spaces::Playground.create!(
        name: "Non-Participating Space",
        owner: user,
        settings: {
          "join_prefix" => "<fieldname>:{{char}}:",
          "join_suffix" => "",
        }
      )

    space.space_memberships.create!(kind: "human", user: user, role: "owner", position: 0)
    alpha = space.space_memberships.create!(kind: "character", character: character_a, role: "member", position: 1)
    beta = space.space_memberships.create!(kind: "character", character: character_b, role: "member", position: 2, participation: "muted")

    conversation = space.conversations.create!(title: "Main")

    prompt = ContextBuilder.new(conversation, speaker: alpha).build(card_mode: "join_exclude_non_participating")
    text = message_contents(prompt)
    assert_includes text, "Alpha desc"
    assert_not_includes text, "Beta desc"

    prompt_when_speaker_non_participating = ContextBuilder.new(conversation, speaker: beta).build(card_mode: "join_exclude_non_participating")
    non_participating_text = message_contents(prompt_when_speaker_non_participating)
    assert_includes non_participating_text, "Beta desc"
  end

  test "history cutoff for regenerate excludes the target message itself" do
    user = users(:admin)

    character =
      Character.create!(
        name: "Alpha",
        status: "ready",
        spec_version: 2,
        data: { "name" => "Alpha", "description" => "Alpha desc" }
      )

    space = Spaces::Playground.create!(name: "Cutoff Space", owner: user)
    human = space.space_memberships.create!(kind: "human", user: user, role: "owner", position: 0)
    speaker = space.space_memberships.create!(kind: "character", character: character, role: "member", position: 1)
    conversation = space.conversations.create!(title: "Main")

    conversation.messages.create!(space_membership: human, role: "user", content: "Hello")
    conversation.messages.create!(space_membership: speaker, role: "assistant", content: "First response")
    target = conversation.messages.create!(space_membership: speaker, role: "assistant", content: "Target response")

    prompt = ContextBuilder.new(conversation, speaker: speaker).build(before_message: target, card_mode: "swap")
    contents = prompt.map { |m| m.fetch(:content) }

    assert_includes contents, "Hello"
    assert_includes contents, "First response"
    assert_not_includes contents, "Target response"
  end
end
