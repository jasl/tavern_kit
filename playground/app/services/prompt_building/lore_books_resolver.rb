# frozen_string_literal: true

module PromptBuilding
  class LoreBooksResolver
    def initialize(space:)
      @space = space
    end

    # Collect lore books from:
    # 1. Global lorebooks attached to the space (via SpaceLorebook)
    # 2. Character-embedded lorebooks from all characters in the space
    # 3. Character-linked lorebooks (via CharacterLorebook)
    #
    # @return [Array<TavernKit::Lore::Book>]
    def call
      books = []

      # 1. Global lorebooks attached to the space
      @space.space_lorebooks.enabled.by_priority.includes(:lorebook).each do |space_lorebook|
        lorebook = space_lorebook.lorebook
        book = lorebook.to_lore_book(source: :global)
        books << book if book.entries.any?
      end

      # 2. & 3. Character lorebooks (embedded and linked)
      character_relation =
        @space.space_memberships.active.ai_characters
          .includes(character: { character_lorebooks: { lorebook: :entries } })

      character_relation.find_each do |membership|
        character = membership.character
        next unless character

        # 2a. Character-embedded lorebooks (from data.character_book)
        if character.character_book.present?
          # Convert Schema to Hash via JSON round-trip for hash manipulation
          book_hash = JSON.parse(character.character_book.to_json)
          effective_book_hash = ::PromptBuilding::WorldInfoBookOverrides.apply(book_hash, space: @space)
          if effective_book_hash
            book = ::TavernKit::Lore::Book.from_hash(effective_book_hash, source: :character)
            books << book
          end
        end

        # 2b. Character-linked primary lorebook (ST: "Link to World Info")
        primary_link = character.character_lorebooks.primary.enabled.first
        if primary_link
          book = primary_link.lorebook.to_lore_book(source: :character_primary)
          books << book if book.entries.any?
        end

        # 2c. Character-linked additional lorebooks (ST: "Extra World Info")
        character.character_lorebooks.additional.enabled.by_priority.each do |link|
          book = link.lorebook.to_lore_book(source: :character_additional)
          books << book if book.entries.any?
        end
      end

      books
    end
  end
end
