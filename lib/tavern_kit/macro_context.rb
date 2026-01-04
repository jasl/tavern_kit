# frozen_string_literal: true

require_relative "group_context"

module TavernKit
  # Context object passed to custom macro procs registered via {MacroRegistry}.
  #
  # This mirrors SillyTavern's "env" macro functions, but provides a Ruby-first,
  # build-time context with access to TavernKit objects.
  #
  # Context fields (for ST-style macros and host extensions):
  # - card / character
  # - user
  # - history
  # - local_store (ChatVariables store for chat-local variables)
  # - preset (for maxPrompt and other preset-driven macros)
  # - generation_type (for ST macros like lastGenerationType)
  # - group (for group-aware macros)
  # - input (current user input; used by lastMessage/lastUserMessage parity)
  class MacroContext
    attr_reader :card, :user, :history, :local_store, :preset, :generation_type, :group, :input

    # @param card [TavernKit::Character] the character
    # @param user [TavernKit::Participant] the user participant
    # @param history [TavernKit::ChatHistory::Base] chat history
    # @param local_store [TavernKit::ChatVariables::Base] chat variables store
    # @param preset [TavernKit::Preset, nil] preset configuration
    # @param generation_type [Symbol, nil] generation type (e.g., :normal, :continue)
    # @param group [GroupContext, nil] group chat context (session data; for group-aware macros)
    # @param input [String, nil] current user input for this build
    def initialize(card:, user:, history:, local_store:, preset: nil, generation_type: nil, group: nil, input: nil)
      @card = card
      @user = user
      @history = history
      @local_store = local_store
      @preset = preset
      @generation_type = generation_type.nil? ? nil : generation_type.to_sym
      @group = group
      @input = input.to_s
    end
  end
end
