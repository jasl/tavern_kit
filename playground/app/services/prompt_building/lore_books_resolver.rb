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
    # 3. Character-linked lorebooks (via CharacterLorebook)
    #
    # @return [Array<TavernKit::Lore::Book>]
    def call
      books = []

      global_lorebook_ids = Set.new(@space.space_lorebooks.enabled.pluck(:lorebook_id).compact)
      chat_lorebook_ids = Set.new

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
          .includes(character: { character_lorebooks: { lorebook: :entries } })

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
        links = Array(character.character_lorebooks)

        primary_link = links.find { |cl| cl.source == "primary" && cl.enabled? }
        if primary_link && !(primary_link.lorebook_id && (global_lorebook_ids.include?(primary_link.lorebook_id) || chat_lorebook_ids.include?(primary_link.lorebook_id)))
          book = primary_link.lorebook.to_lore_book(source: :character_primary)
          book = ::PromptBuilding::WorldInfoBookOverrides.apply(book, space: @space) || book
          books << book if book.entries.any?
        end

        # 2c. Character-linked additional lorebooks (ST: "Extra World Info")
        links
          .select { |cl| cl.source == "additional" && cl.enabled? }
          .sort_by(&:priority)
          .each do |link|
          # ST parity: skip character lorebook if it is already activated via global/chat.
          next if link.lorebook_id && (global_lorebook_ids.include?(link.lorebook_id) || chat_lorebook_ids.include?(link.lorebook_id))

          book = link.lorebook.to_lore_book(source: :character_additional)
          book = ::PromptBuilding::WorldInfoBookOverrides.apply(book, space: @space) || book
          books << book if book.entries.any?
        end
      end

      books
    end
  end
end
