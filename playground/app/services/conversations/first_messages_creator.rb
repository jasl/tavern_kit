# frozen_string_literal: true

# Creates the initial greeting/first messages for a conversation.
#
# This is a workflow spanning multiple models (Conversation + SpaceMembership + Character),
# so it lives in the service layer. The Conversation model keeps a small delegator.
#
module Conversations
  class FirstMessagesCreator
    def self.call(conversation:)
      new(conversation: conversation).call
    end

    def initialize(conversation:)
      @conversation = conversation
      @space = conversation.space
    end

    # @return [Array<Message>]
    def call
      created = []

      @space.character_space_memberships.by_position.includes(:character).each do |membership|
        first_mes = membership.character&.first_mes
        next if first_mes.blank?

        created << @conversation.messages.create!(
          space_membership: membership,
          role: "assistant",
          content: first_mes
        )
      end

      created
    end
  end
end
