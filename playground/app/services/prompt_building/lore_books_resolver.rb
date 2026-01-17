# frozen_string_literal: true

require "set"

module PromptBuilding
  class LoreBooksResolver
    def initialize(space:, conversation: nil)
      @space = space
      @conversation = conversation
    end

    # Collect lore books from:
    # 0. Conversation lorebooks attached to the chat (ST: "Chat Lore")
    # 1. Global lorebooks attached to the space (via SpaceLorebook)
    # 2. Character-embedded lorebooks from all characters in the space
    # 3. Character-linked lorebooks (name-based soft links: data.extensions.world/extra_worlds)
    #
    # @return [Array<TavernKit::Lore::Book>]
    def call
      books = []

      global_lorebook_ids = Set.new(@space.space_lorebooks.enabled.pluck(:lorebook_id).compact)
      chat_lorebook_ids = Set.new
      character_lorebook_ids = Set.new

      # 0. Conversation lorebooks (ST: Chat Lore)
      if @conversation
        @conversation.conversation_lorebooks.enabled.by_priority.includes(lorebook: :entries).each do |conversation_lorebook|
          lorebook = conversation_lorebook.lorebook
          next unless lorebook

          # ST parity: if this lorebook is also active globally, skip the chat binding.
          next if lorebook.id && global_lorebook_ids.include?(lorebook.id)

          book = lorebook.to_lore_book(source: :chat)
          book = ::PromptBuilding::WorldInfoBookOverrides.apply(book, space: @space) || book
          books << book if book.entries.any?

          chat_lorebook_ids.add(lorebook.id) if lorebook.id
        end
      end

      # 1. Global lorebooks attached to the space
      @space.space_lorebooks.enabled.by_priority.includes(lorebook: :entries).each do |space_lorebook|
        lorebook = space_lorebook.lorebook
        source = (space_lorebook.source.to_s.presence || "global").to_sym
        global_lorebook_ids.add(lorebook.id) if lorebook&.id
        book = lorebook.to_lore_book(source: source)
        book = ::PromptBuilding::WorldInfoBookOverrides.apply(book, space: @space) || book
        books << book if book.entries.any?
      end

      # 2. & 3. Character lorebooks (embedded and linked)
      character_relation =
        @space.space_memberships.active.ai_characters.by_position
          .includes(:character)

      character_relation.each do |membership|
        character = membership.character
        next unless character

        # 2a. Character-embedded lorebooks (from data.character_book)
        if character.character_book.present?
          # Convert Schema to Hash via JSON round-trip for hash manipulation
          book_hash = JSON.parse(character.character_book.to_json)
          book_hash = ::PromptBuilding::WorldInfoBookOverrides.apply(book_hash, space: @space) || book_hash
          book = ::TavernKit::Lore::Book.from_hash(book_hash, source: :character)
          books << book if book.entries.any?
        end

        # 2b. Character-linked primary lorebook (ST: "Link to World Info")
        primary_lorebook = find_lorebook_for_world_name(character.data&.world_name)

        if primary_lorebook&.id &&
            !character_lorebook_ids.include?(primary_lorebook.id) &&
            !global_lorebook_ids.include?(primary_lorebook.id) &&
            !chat_lorebook_ids.include?(primary_lorebook.id)
          book = primary_lorebook.to_lore_book(source: :character_primary)
          book = ::PromptBuilding::WorldInfoBookOverrides.apply(book, space: @space) || book
          books << book if book.entries.any?
          character_lorebook_ids.add(primary_lorebook.id)
        end

        # 2c. Character-linked additional lorebooks (extra_worlds)
        Array(character.data&.extra_world_names).uniq.each do |world_name|
          lorebook = find_lorebook_for_world_name(world_name)
          next unless lorebook&.id
          next if character_lorebook_ids.include?(lorebook.id)
          next if global_lorebook_ids.include?(lorebook.id) || chat_lorebook_ids.include?(lorebook.id)

          book = lorebook.to_lore_book(source: :character_additional)
          book = ::PromptBuilding::WorldInfoBookOverrides.apply(book, space: @space) || book
          books << book if book.entries.any?
          character_lorebook_ids.add(lorebook.id)
        end
      end

      books
    end

    private

    def find_lorebook_for_world_name(name)
      return nil unless @space&.owner

      @name_resolver ||= Lorebooks::NameResolver.new
      @name_resolver.resolve(user: @space.owner, name: name)
    end
  end
end
