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

    test "includes character additional lorebooks from data.extensions.extra_worlds" do
      user = users(:admin)
      space = Spaces::Playground.create!(name: "LoreBooksResolver Extra Worlds Space", owner: user)
      conversation = space.conversations.create!(title: "Main")

      extra1 = Lorebook.create!(name: "Extra One", user: user, visibility: "private")
      extra1.entries.create!(keys: ["extra"], content: "EXTRA_ONE_ENTRY")

      extra2 = Lorebook.create!(name: "Extra Two", user: user, visibility: "private")
      extra2.entries.create!(keys: ["extra"], content: "EXTRA_TWO_ENTRY")

      character =
        Character.create!(
          name: "Extra Worlds Character",
          user: user,
          status: "ready",
          visibility: "private",
          spec_version: 2,
          file_sha256: "extra_worlds_#{SecureRandom.hex(8)}",
          data: {
            name: "Extra Worlds Character",
            group_only_greetings: [],
            extensions: { extra_worlds: ["Extra One", "Extra Two"] },
          }
        )
      space.space_memberships.create!(kind: "character", role: "member", character: character, position: 0)

      books = LoreBooksResolver.new(space: space, conversation: conversation).call

      assert books.find { |b| b.name == "Extra One" && b.source == :character_additional }
      assert books.find { |b| b.name == "Extra Two" && b.source == :character_additional }
    end
  end
end

module PromptBuilding
  class LoreBooksResolverCacheInvalidationTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    test "invalidates negative cache on create for primary character-linked lorebook (world)" do
      user = users(:admin)
      store = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(store)

      space = Spaces::Playground.create!(name: "LoreBooksResolver Cache Invalidation World Space", owner: user)
      conversation = space.conversations.create!(title: "Main")

      character =
        Character.create!(
          name: "World Linked Character (Cache Invalidation)",
          user: user,
          status: "ready",
          visibility: "private",
          spec_version: 2,
          file_sha256: "world_linked_cache_invalidation_#{SecureRandom.hex(8)}",
          data: {
            name: "World Linked Character (Cache Invalidation)",
            group_only_greetings: [],
            extensions: { world: "World One" },
          }
        )
      space.space_memberships.create!(kind: "character", role: "member", character: character, position: 0)

      books = LoreBooksResolver.new(space: space, conversation: conversation).call
      assert_nil books.find { |b| b.name == "World One" }

      lorebook = Lorebook.create!(name: "World One", user: user, visibility: "private")
      lorebook.entries.create!(keys: ["world"], content: "WORLD_ONE_ENTRY", enabled: true)

      books = LoreBooksResolver.new(space: space, conversation: conversation).call
      book = books.find { |b| b.name == "World One" }

      assert book
      assert_equal :character_primary, book.source
      assert_equal "WORLD_ONE_ENTRY", book.entries.first&.content
    ensure
      space&.destroy!
      character&.destroy!
      lorebook&.destroy!
    end

    test "invalidates negative cache on create for additional character-linked lorebooks (extra_worlds)" do
      user = users(:admin)
      store = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(store)

      space = Spaces::Playground.create!(name: "LoreBooksResolver Cache Invalidation Extra Worlds Space", owner: user)
      conversation = space.conversations.create!(title: "Main")

      character =
        Character.create!(
          name: "Extra Worlds Character (Cache Invalidation)",
          user: user,
          status: "ready",
          visibility: "private",
          spec_version: 2,
          file_sha256: "extra_worlds_cache_invalidation_#{SecureRandom.hex(8)}",
          data: {
            name: "Extra Worlds Character (Cache Invalidation)",
            group_only_greetings: [],
            extensions: { extra_worlds: ["Extra One", "Extra Two"] },
          }
        )
      space.space_memberships.create!(kind: "character", role: "member", character: character, position: 0)

      books = LoreBooksResolver.new(space: space, conversation: conversation).call
      assert_nil books.find { |b| b.name == "Extra One" }
      assert_nil books.find { |b| b.name == "Extra Two" }

      extra1 = Lorebook.create!(name: "Extra One", user: user, visibility: "private")
      extra1.entries.create!(keys: ["extra"], content: "EXTRA_ONE_ENTRY", enabled: true)

      extra2 = Lorebook.create!(name: "Extra Two", user: user, visibility: "private")
      extra2.entries.create!(keys: ["extra"], content: "EXTRA_TWO_ENTRY", enabled: true)

      books = LoreBooksResolver.new(space: space, conversation: conversation).call
      assert books.find { |b| b.name == "Extra One" && b.source == :character_additional }
      assert books.find { |b| b.name == "Extra Two" && b.source == :character_additional }
    ensure
      space&.destroy!
      character&.destroy!
      extra1&.destroy!
      extra2&.destroy!
    end
  end
end
