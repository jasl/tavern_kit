# frozen_string_literal: true

require "base64"
require "json"
require "securerandom"
require "zlib"

require "js_regex_to_ruby"
require "tiktoken_ruby"

require_relative "tavern_kit/version"

require_relative "tavern_kit/constants"
require_relative "tavern_kit/coerce"
require_relative "tavern_kit/errors"
require_relative "tavern_kit/utils"
require_relative "tavern_kit/group_context"
require_relative "tavern_kit/injection_registry"
require_relative "tavern_kit/hook_registry"

require_relative "tavern_kit/participant"
require_relative "tavern_kit/user"

require_relative "tavern_kit/png/parser"
require_relative "tavern_kit/png/writer"

require_relative "tavern_kit/character"
require_relative "tavern_kit/character_card"

require_relative "tavern_kit/chat_variables"
require_relative "tavern_kit/macro/invocation"
require_relative "tavern_kit/macro/phase"
require_relative "tavern_kit/macro/environment"
require_relative "tavern_kit/macro/v1/engine"
require_relative "tavern_kit/macro/v2/engine"
require_relative "tavern_kit/macro_context"
require_relative "tavern_kit/macro_registry"

require_relative "tavern_kit/token_estimator"

require_relative "tavern_kit/lore/key_list"
require_relative "tavern_kit/lore/entry"
require_relative "tavern_kit/lore/book"
require_relative "tavern_kit/lore/result"
require_relative "tavern_kit/lore/engine"

require_relative "tavern_kit/instruct"
require_relative "tavern_kit/context_template"
require_relative "tavern_kit/preset"

require_relative "tavern_kit/prompt/message"
require_relative "tavern_kit/chat_history"
require_relative "tavern_kit/prompt/block"
require_relative "tavern_kit/prompt/dialects"
require_relative "tavern_kit/prompt/example_parser"
require_relative "tavern_kit/prompt/expander_vars"
require_relative "tavern_kit/prompt/prompt_entry"
require_relative "tavern_kit/prompt/plan"
require_relative "tavern_kit/prompt/trimmer"

# Pipeline system (middleware-based prompt construction)
require_relative "tavern_kit/prompt/context"
require_relative "tavern_kit/prompt/pipeline"
require_relative "tavern_kit/prompt/middleware"
require_relative "tavern_kit/prompt/dsl"

module TavernKit
  class << self
    # Load a character from any supported source.
    # @param input [String, Hash] file path, JSON string, or Hash
    # @return [Character]
    def load_character(input)
      CharacterCard.load(input)
    end

    # Load a preset from file or hash. Auto-detects SillyTavern format.
    # @param input [String, Hash] file path or Hash
    # @return [Preset]
    def load_preset(input)
      return Preset.new unless input
      return load_preset(JSON.parse(File.read(input))) if input.is_a?(String)
      return Preset.new unless input.is_a?(Hash)

      h = input.transform_keys { |k| k.to_s.to_sym }
      return Preset.from_st_preset_json(input) if h[:prompts] || h[:prompt_order]

      h[:prompt_entries] = Array(h[:prompt_entries]).map { |e| e.is_a?(Prompt::PromptEntry) ? e : Prompt::PromptEntry.from_hash(e) } if h[:prompt_entries]
      h[:authors_note_position] = Coerce.authors_note_position(h[:authors_note_position]) if h[:authors_note_position]
      h[:authors_note_role] = Coerce.role(h[:authors_note_role]) if h[:authors_note_role]
      h[:character_lore_insertion_strategy] = Coerce.insertion_strategy(h[:character_lore_insertion_strategy]) if h[:character_lore_insertion_strategy]
      h[:examples_behavior] = Coerce.examples_behavior(h[:examples_behavior]) if h[:examples_behavior]
      h.compact!

      Preset.new(**h)
    end

    # Global custom macro registry.
    # @return [MacroRegistry]
    def macros
      @macros ||= MacroRegistry.new
    end

    # Returns the default prompt pipeline.
    # @return [Prompt::Pipeline]
    def pipeline
      @pipeline ||= Prompt::Pipeline.default
    end

    # Build a prompt using the DSL-based pipeline.
    #
    # This is the primary API for building prompts. It uses a middleware pipeline
    # that can be customized and extended.
    #
    # @example Block style (recommended)
    #   plan = TavernKit.build do
    #     character my_char
    #     user my_user
    #     message "Hello!"
    #   end
    #
    # @example Keyword arguments
    #   plan = TavernKit.build(
    #     character: my_char,
    #     user: my_user,
    #     message: "Hello!"
    #   )
    #
    # @example With custom middleware
    #   plan = TavernKit.build do
    #     character my_char
    #     use MyCustomMiddleware
    #     replace :trimming, MyTrimmer
    #   end
    #
    # @param character [Character, nil] character card
    # @param user [Participant, nil] user participant
    # @param message [String, nil] user message
    # @param preset [Preset, nil] preset configuration
    # @param history [ChatHistory::Base, nil] chat history
    # @param lore_books [Array<Lore::Book>] lore books
    # @param greeting_index [Integer, nil] greeting index (0 = first_mes, 1+ = alternate)
    # @param generation_type [Symbol, String, Integer, nil] prompt trigger type (normal/continue/impersonate/swipe/regenerate/quiet)
    # @param group [GroupContext, nil] group chat context
    # @param lore_engine [Lore::Engine, nil] lore evaluation engine
    # @param macro_vars [Hash, nil] macro variables (builder vars layer)
    # @param injection_registry [InjectionRegistry, nil] programmatic injections (STscript /inject equivalent)
    # @param hook_registry [HookRegistry, nil] before/after build hooks
    # @param token_estimator [TokenEstimator::Base, nil] token estimator override
    # @param expander [#expand, nil] macro expander override
    # @param macro_engine [Symbol, String, nil] macro engine selector (:legacy, :v2) (ignored if expander is provided)
    # @param macro_registry [MacroRegistry, nil] custom macro registry
    # @param force_world_info [Array<Hash>, nil] forced world info activations
    # @param warning_handler [Symbol, #call, nil] :default, nil, or callable
    # @param strict [Boolean] strict mode (raise on warnings)
    # @param pipeline [Prompt::Pipeline, nil] custom pipeline
    # @yield [Prompt::DSL] DSL configuration block
    # @return [Prompt::Plan]
    def build(
      character: nil,
      user: nil,
      message: nil,
      preset: nil,
      history: nil,
      lore_books: [],
      greeting_index: nil,
      generation_type: nil,
      group: nil,
      lore_engine: nil,
      macro_vars: nil,
      injection_registry: nil,
      hook_registry: nil,
      token_estimator: nil,
      expander: nil,
      macro_engine: nil,
      macro_registry: nil,
      force_world_info: nil,
      warning_handler: :default,
      strict: false,
      pipeline: nil,
      &block
    )
      if block
        coerced_character = coerce_character(character)
        coerced_user = coerce_user(user)
        coerced_preset = coerce_preset(preset)
        coerced_history = coerce_history(history)
        coerced_lore_books = lore_books.any? ? coerce_lore_books(lore_books) : []
        coerced_generation_type = generation_type ? Coerce.generation_type(generation_type) : nil

        Prompt::DSL.build(pipeline: pipeline) do
          # Apply provided keyword arguments
          character(coerced_character) if coerced_character

          user(coerced_user) if coerced_user

          preset(coerced_preset) if coerced_preset

          history(coerced_history) if coerced_history

          lore_books(coerced_lore_books) if coerced_lore_books.any?
          message(message.to_s) if message
          greeting(greeting_index) unless greeting_index.nil?

          generation_type(coerced_generation_type) if coerced_generation_type
          group(group) if group
          lore_engine(lore_engine) if lore_engine
          macro_vars(macro_vars) if macro_vars
          injection_registry(injection_registry) if injection_registry
          hook_registry(hook_registry) if hook_registry
          token_estimator(token_estimator) if token_estimator
          macro_registry(macro_registry) if macro_registry
          force_world_info(force_world_info) if force_world_info
          warning_handler(warning_handler)
          strict(strict)

          if expander
            expander(expander)
          elsif macro_engine
            macro_engine(macro_engine)
          end

          # Evaluate the user's block
          instance_eval(&block)
        end
      else
        # No block - use keyword arguments directly
        dsl = Prompt::DSL.new(pipeline: pipeline)
        coerced_character = coerce_character(character)
        dsl.character(coerced_character) if coerced_character

        coerced_user = coerce_user(user)
        dsl.user(coerced_user) if coerced_user

        coerced_preset = coerce_preset(preset)
        dsl.preset(coerced_preset) if coerced_preset

        coerced_history = coerce_history(history)
        dsl.history(coerced_history) if coerced_history

        dsl.lore_books(coerce_lore_books(lore_books)) if lore_books.any?
        dsl.message(message.to_s) if message
        dsl.greeting(greeting_index) unless greeting_index.nil?

        dsl.generation_type(Coerce.generation_type(generation_type)) if generation_type
        dsl.group(group) if group
        dsl.lore_engine(lore_engine) if lore_engine
        dsl.macro_vars(macro_vars) if macro_vars
        dsl.injection_registry(injection_registry) if injection_registry
        dsl.hook_registry(hook_registry) if hook_registry
        dsl.token_estimator(token_estimator) if token_estimator
        dsl.macro_registry(macro_registry) if macro_registry
        dsl.force_world_info(force_world_info) if force_world_info
        dsl.warning_handler(warning_handler)
        dsl.strict(strict)

        if expander
          dsl.expander(expander)
        elsif macro_engine
          dsl.macro_engine(macro_engine)
        end

        dsl.build
      end
    end

    # Build messages directly using the pipeline.
    #
    # Convenience method that builds a prompt and converts to messages in one step.
    #
    # @example
    #   messages = TavernKit.to_messages(dialect: :openai) do
    #     character my_char
    #     user my_user
    #     message "Hello!"
    #   end
    #
    # @param dialect [Symbol] output dialect (:openai, :anthropic, etc.)
    # @param squash_system_messages [Boolean, nil] override squashing (OpenAI only)
    # @param pipeline [Prompt::Pipeline, nil] custom pipeline
    # @yield [Prompt::DSL] DSL configuration block
    # @return [Array<Hash>]
    def to_messages(dialect: :openai, squash_system_messages: nil, pipeline: nil, **build_kwargs, &block)
      plan = build(pipeline: pipeline, **build_kwargs, &block)

      squash =
        if !squash_system_messages.nil?
          squash_system_messages
        else
          preset = coerce_preset(build_kwargs[:preset])
          preset&.squash_system_messages || false
        end

      plan.to_messages(dialect: dialect, squash_system_messages: squash)
    end

    private

    def coerce_character(input)
      return input if input.nil? || input.is_a?(Character)

      load_character(input)
    end

    def coerce_user(input)
      return input if input.nil? || input.respond_to?(:persona_text)
      return User.new(name: input.to_s) if input.is_a?(String)
      return User.new(name: "User") unless input.is_a?(Hash)

      h = input.transform_keys { |k| k.to_s.to_sym }
      User.new(name: h[:name] || "User", persona: h[:persona])
    end

    def coerce_preset(input)
      return input if input.nil? || input.is_a?(Preset)
      return nil if input.is_a?(Hash) && input.empty?

      load_preset(input)
    end

    def coerce_history(input)
      return input if input.nil? || (input.respond_to?(:each) && input.respond_to?(:append) && !input.is_a?(Array))

      ChatHistory.wrap(input)
    end

    def coerce_lore_books(input)
      Array(input).compact.map do |item|
        next item if item.is_a?(Lore::Book)
        next Lore::Book.load_file(item, source: :global) if item.is_a?(String)

        Lore::Book.from_hash(item, source: :global)
      end
    end
  end
end
