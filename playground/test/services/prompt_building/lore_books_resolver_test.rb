# frozen_string_literal: true

require "test_helper"

module PromptBuilding
  class LoreBooksResolverTest < ActiveSupport::TestCase
    test "includes character primary lorebook from data.extensions.world" do
      user = users(:admin)
      space = Spaces::Playground.create!(name: "LoreBooksResolver World Space", owner: user)
      conversation = space.conversations.create!(title: "Main")

      lorebook = Lorebook.create!(name: "World One", user: user, visibility: "private")
      lorebook.entries.create!(keys: ["world"], content: "WORLD_ONE_ENTRY")

      character =
        Character.create!(
          name: "World Linked Character",
          user: user,
          status: "ready",
          visibility: "private",
          spec_version: 2,
          file_sha256: "world_linked_#{SecureRandom.hex(8)}",
          data: {
            name: "World Linked Character",
            group_only_greetings: [],
            extensions: { world: "World One" },
          }
        )
      space.space_memberships.create!(kind: "character", role: "member", character: character, position: 0)

      books = LoreBooksResolver.new(space: space, conversation: conversation).call
      book = books.find { |b| b.name == "World One" }

      assert book
      assert_equal :character_primary, book.source
      assert_equal 1, book.entries.size
      assert_equal "WORLD_ONE_ENTRY", book.entries.first.content
    end

    test "dedupes character world lorebook across multiple characters" do
      user = users(:admin)
      space = Spaces::Playground.create!(name: "LoreBooksResolver Dedupe Space", owner: user)
      conversation = space.conversations.create!(title: "Main")

      lorebook = Lorebook.create!(name: "Shared World", user: user, visibility: "private")
      lorebook.entries.create!(keys: ["world"], content: "SHARED_WORLD_ENTRY")

      [1, 2].each do |idx|
        character =
          Character.create!(
            name: "World Linked #{idx}",
            user: user,
            status: "ready",
            visibility: "private",
            spec_version: 2,
            file_sha256: "world_linked_#{idx}_#{SecureRandom.hex(8)}",
            data: {
              name: "World Linked #{idx}",
              group_only_greetings: [],
              extensions: { world: "Shared World" },
            }
          )
        space.space_memberships.create!(kind: "character", role: "member", character: character, position: idx)
      end

      books = LoreBooksResolver.new(space: space, conversation: conversation).call

      assert_equal 1, books.count { |b| b.name == "Shared World" }
    end
  end
end
