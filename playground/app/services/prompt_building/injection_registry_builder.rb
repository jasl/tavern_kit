# frozen_string_literal: true

module PromptBuilding
  class InjectionRegistryBuilder
    ST_DEFAULT_DEPTH_PROMPT_DEPTH = 4
    ST_DEFAULT_DEPTH_PROMPT_ROLE = :system

    def initialize(space:, current_character_membership:, user:, history:, preset:, group:, user_message:, generation_type:, macro_vars:, card_handling_mode_override:)
      @space = space
      @current_character_membership = current_character_membership
      @user = user
      @history = history
      @preset = preset
      @group = group
      @user_message = user_message
      @generation_type = generation_type
      @macro_vars = macro_vars || {}
      @card_handling_mode_override = card_handling_mode_override.to_s.presence
    end

    # @return [TavernKit::InjectionRegistry]
    def call
      registry = ::TavernKit::InjectionRegistry.new

      return registry unless group_chat_join_mode?

      add_group_depth_prompts!(registry)
      registry
    end

    private

    def group_chat_join_mode?
      @group.present? && %w[append append_disabled].include?(normalized_card_handling_mode)
    end

    def normalized_card_handling_mode
      return @card_handling_mode_override if @card_handling_mode_override.present?
      return "swap" unless @space.respond_to?(:card_handling_mode)

      @space.card_handling_mode.to_s.presence || "swap"
    end

    # ST behavior reference: tmp/SillyTavern/public/scripts/group-chats.js getGroupDepthPrompts
    #
    # - Only active (not muted) members get their depth prompts injected.
    # - The current speaker is always included (even if muted), but TavernKit already
    #   injects the speaker's depth prompt via character extensions, so we skip it here
    #   to avoid duplicates.
    def add_group_depth_prompts!(registry)
      scenario_override = @space.prompt_settings&.scenario_override.to_s.presence

      memberships = @space.space_memberships.active.ai_characters.by_position.includes(:character).to_a

      if @current_character_membership&.character? && memberships.none? { |m| m.id == @current_character_membership.id }
        memberships << @current_character_membership
      end

      expander = ::TavernKit::Macro::V2::Engine.new

      memberships.each do |membership|
        next unless membership.character
        next if @current_character_membership && membership.id == @current_character_membership.id # TavernKit handles current character depth prompt.
        next unless membership.participation_active?

        participant = ::PromptBuilding::ParticipantAdapter.to_participant(membership)
        next unless participant.is_a?(::TavernKit::Character)

        depth_prompt = read_depth_prompt(participant)
        next unless depth_prompt

        template = depth_prompt.fetch(:prompt).to_s.strip
        next if template.empty?

        expanded = expand_for_member(template, expander: expander, participant: apply_scenario_override(participant, scenario_override))
        next if expanded.to_s.strip.empty?

        registry.register(
          id: "group_depth_prompt:#{membership.id}",
          content: expanded,
          position: :chat,
          depth: depth_prompt.fetch(:depth),
          role: depth_prompt.fetch(:role),
          scan: false,
          ephemeral: false
        )
      end
    end

    def read_depth_prompt(character)
      extensions = character.data.extensions
      return nil unless extensions.is_a?(Hash)

      dp = extensions["depth_prompt"] || extensions[:depth_prompt]
      return nil unless dp.is_a?(Hash)

      prompt = dp["prompt"] || dp[:prompt]
      depth = dp["depth"] || dp[:depth]
      role = dp["role"] || dp[:role]

      depth = Integer(depth || ST_DEFAULT_DEPTH_PROMPT_DEPTH)
      depth = 0 if depth.negative?
      role = normalize_role(role) || ST_DEFAULT_DEPTH_PROMPT_ROLE

      { prompt: prompt, depth: depth, role: role }
    rescue ArgumentError, TypeError
      nil
    end

    def normalize_role(value)
      case value.to_s.downcase
      when "system" then :system
      when "user" then :user
      when "assistant" then :assistant
      else nil
      end
    end

    def apply_scenario_override(character, scenario_override)
      return character unless scenario_override

      overridden_data = character.data.with(scenario: scenario_override.to_s)
      ::TavernKit::Character.new(data: overridden_data, source_version: character.source_version, raw: character.raw)
    end

    def expand_for_member(template, expander:, participant:)
      ctx =
        ::TavernKit::Prompt::Context.new(
          character: participant,
          user: @user,
          history: @history,
          preset: @preset,
          group: @group,
          user_message: @user_message.to_s,
          generation_type: @generation_type,
          macro_vars: @macro_vars
        )

      ctx.variables_store = ::TavernKit::ChatVariables.wrap(@macro_vars[:local_store])

      vars = ::TavernKit::Prompt::ExpanderVars.build(ctx)
      expander.expand(template, vars, allow_outlets: false)
    end
  end
end
