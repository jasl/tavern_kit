# frozen_string_literal: true

# Creates a space with its initial conversation + memberships + greeting messages.
#
# This is intentionally Rails-app-layer code (uses AR and transactions).
#
module Spaces
  class Creator
    def self.call(space_class:, attributes:, user:, characters:)
      new(space_class: space_class, attributes: attributes, user: user, characters: characters).call
    end

    def initialize(space_class:, attributes:, user:, characters:)
      @space_class = space_class
      @attributes = attributes
      @user = user
      @characters = Array(characters)
    end

    def call
      raise ArgumentError, "At least one character is required" if @characters.blank?

      @space_class.transaction do
        attrs = @attributes.to_h.symbolize_keys

        attrs[:owner] = @user
        attrs[:name] = default_name_for(@characters) if attrs[:name].blank?

        @space_class.create!(attrs).tap do |space|
          conversation = space.conversations.create!(title: "Main")
          SpaceMemberships::Grant.call(space: space, actors: [@user, *@characters])
          conversation.create_first_messages!
        end
      end
    end

    private

    def default_name_for(characters)
      names = Array(characters).filter_map(&:name).map(&:strip).compact_blank
      return "New Space" if names.empty?
      return names.first if names.size == 1

      names.join(", ").truncate(60)
    end
  end
end
