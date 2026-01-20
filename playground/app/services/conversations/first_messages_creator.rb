# frozen_string_literal: true

# Creates the initial greeting/first messages for a conversation.
#
# This is a workflow spanning multiple models (Conversation + SpaceMembership + Character),
# so it lives in the service layer. The Conversation model keeps a small delegator.
#
# SillyTavern behavior: Macros like {{char}} and {{user}} are expanded at message
# creation time, not at display time. This ensures the stored message reflects
# the actual conversation context (character/user names) at the time it was created.
# See: tmp/SillyTavern/public/scripts/group-chats.js getFirstCharacterMessage()
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

      # Resolve user participant for macro expansion
      user_participant = resolve_user_participant

      @space.character_space_memberships.by_position.includes(:character).each do |membership|
        first_mes = membership.character&.first_mes
        next if first_mes.blank?

        # Expand macros ({{char}}, {{user}}, etc.) before storing the message.
        # This matches SillyTavern behavior where substituteParams() is called
        # on the first message text at creation time.
        expanded_content = expand_macros(first_mes, membership, user_participant)

        created << @conversation.messages.create!(
          space_membership: membership,
          role: "assistant",
          content: expanded_content
        )
      end

      created
    end

    private

    # Resolve the user participant for macro expansion.
    #
    # @return [TavernKit::User, nil]
    def resolve_user_participant
      # Eager load character and user to avoid N+1 in display_name
      memberships = @space.space_memberships.active.includes(:character, :user)
      user_membership = memberships.find { |m| m.user? && !m.auto_enabled? } ||
                        memberships.find(&:user?)

      return nil unless user_membership

      ::PromptBuilding::ParticipantAdapter.to_user_participant(user_membership)
    end

    # Expand TavernKit macros in the message content.
    #
    # @param content [String] raw message content with macros
    # @param membership [SpaceMembership] character membership
    # @param user_participant [TavernKit::User, nil] user participant
    # @return [String] expanded content
    def expand_macros(content, membership, user_participant)
      return content if content.blank?

      character = membership.character
      return content unless character

      # Build a TavernKit Character from the ActiveRecord Character
      tavern_character = ::PromptBuilding::CharacterAdapter.to_tavern_kit_character(character)

      # Build macro expansion context
      ctx = ::TavernKit::Prompt::Context.new(
        character: tavern_character,
        user: user_participant,
        history: ::TavernKit::ChatHistory.new,
        generation_type: :normal
      )

      # Build macro variables
      vars = ::TavernKit::Prompt::ExpanderVars.build(ctx)

      # Use the macro expander to expand the content
      expander = ::TavernKit::Macro::SillyTavernV2::Engine.new
      expander.expand(content, vars, allow_outlets: false)
    end
  end
end
