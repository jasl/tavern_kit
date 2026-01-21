# frozen_string_literal: true

module TavernKit
  module Prompt
    # Context object that flows through the middleware pipeline.
    #
    # The context carries all input data, intermediate state, and output
    # through each middleware stage. Middlewares can read and modify the
    # context to transform inputs into the final prompt plan.
    #
    # @example Basic usage
    #   ctx = Context.new(
    #     character: char,
    #     user: user,
    #     user_message: "Hello!"
    #   )
    #   pipeline.execute(ctx)
    #   ctx.plan  # => Prompt::Plan
    #
    class Context
      # ============================================
      # Input data (typically set at initialization)
      # ============================================

      # @return [Character, nil] the character card
      attr_accessor :character

      # @return [Participant, nil] the user/persona
      attr_accessor :user

      # @return [ChatHistory::Base, nil] chat history
      attr_accessor :history

      # @return [String] current user message
      attr_accessor :user_message

      # @return [Preset] preset configuration
      attr_accessor :preset

      # @return [Symbol] generation type (:normal, :continue, :impersonate, etc.)
      attr_accessor :generation_type

      # @return [GroupContext, nil] group chat context
      attr_accessor :group

      # @return [Array<Lore::Book>] global lore books
      attr_accessor :lore_books

      # @return [Integer, nil] greeting index
      attr_accessor :greeting_index

      # @return [Hash, nil] per-chat Author's Note overrides
      attr_accessor :authors_note_overrides

      # @return [Array<Hash>] forced World Info activations
      attr_accessor :forced_world_info_activations

      # @return [InjectionRegistry] injection registry
      attr_accessor :injection_registry

      # @return [HookRegistry] hook registry
      attr_accessor :hook_registry

      # @return [Hash] macro variables
      attr_accessor :macro_vars

      # ============================================
      # Intermediate state (set by middlewares)
      # ============================================

      # @return [Lore::Result, nil] lore engine evaluation result
      attr_accessor :lore_result

      # @return [Hash{String => Object}] World Info outlets
      attr_accessor :outlets

      # @return [Array<PromptEntry>] filtered prompt entries
      attr_accessor :prompt_entries

      # @return [Hash{String => Array<Block>}] pinned group blocks
      attr_accessor :pinned_groups

      # @return [Array<Block>] compiled blocks
      attr_accessor :blocks

      # @return [Array<Block>, nil] continue blocks for :continue generation
      attr_accessor :continue_blocks

      # @return [ChatVariables::Base] variables store
      attr_accessor :variables_store

      # @return [Array<String>] scan messages for World Info
      attr_accessor :scan_messages

      # @return [Hash] scan context for World Info
      attr_accessor :scan_context

      # @return [Array<String>] scan injects for World Info
      attr_accessor :scan_injects

      # @return [Array<String>] chat scan messages for prompt entry conditions
      attr_accessor :chat_scan_messages

      # @return [Integer] default chat depth for scanning
      attr_accessor :default_chat_depth

      # @return [Integer] user turn count
      attr_accessor :turn_count

      # ============================================
      # Output
      # ============================================

      # @return [Plan, nil] the final prompt plan
      attr_accessor :plan

      # @return [String, nil] resolved greeting text
      attr_accessor :resolved_greeting

      # @return [Integer, nil] resolved greeting index
      attr_accessor :resolved_greeting_index

      # @return [Hash, nil] trim report from Trimmer
      attr_accessor :trim_report

      # ============================================
      # Configuration
      # ============================================

      # @return [TokenEstimator::Base] token estimator
      attr_accessor :token_estimator

      # @return [Lore::Engine] lore engine
      attr_accessor :lore_engine

      # @return [#expand] macro expander
      attr_accessor :expander

      # @return [MacroRegistry] custom macro registry
      attr_accessor :macro_registry

      # @return [MacroRegistry] builtins macro registry
      attr_accessor :macro_builtins_registry

      # @return [Symbol, Proc, nil] pinned group resolver
      attr_accessor :pinned_group_resolver

      # @return [Symbol, Proc, nil] warning handler
      attr_accessor :warning_handler

      # @return [Boolean] strict mode flag
      attr_accessor :strict

      # ============================================
      # Warnings and metadata
      # ============================================

      # @return [Array<String>] collected warnings
      attr_reader :warnings

      # @return [Hash] arbitrary metadata storage
      attr_reader :metadata

      def initialize(**attrs)
        @warnings = []
        @metadata = {}
        @lore_books = []
        @forced_world_info_activations = []
        @outlets = {}
        @pinned_groups = {}
        @blocks = []
        @generation_type = :normal
        @strict = false
        @warning_handler = :default # Default to printing to stderr

        attrs.each do |key, value|
          setter = :"#{key}="
          if respond_to?(setter)
            public_send(setter, value)
          else
            @metadata[key] = value
          end
        end
      end

      # Create a shallow copy suitable for pipeline branching.
      #
      # @return [Context]
      def dup
        copy = super
        copy.instance_variable_set(:@warnings, @warnings.dup)
        copy.instance_variable_set(:@metadata, @metadata.dup)
        copy.instance_variable_set(:@lore_books, @lore_books.dup)
        copy.instance_variable_set(:@forced_world_info_activations, @forced_world_info_activations.dup)
        copy.instance_variable_set(:@outlets, @outlets.dup)
        copy.instance_variable_set(:@pinned_groups, @pinned_groups.dup)
        copy.instance_variable_set(:@blocks, @blocks.dup)
        copy
      end

      # Emit a warning message.
      #
      # In strict mode, raises StrictModeError instead of collecting.
      #
      # @param message [String] warning message
      # @return [nil]
      def warn(message)
        msg = message.to_s

        if @strict
          @warnings << msg
          raise TavernKit::StrictModeError, msg
        end

        @warnings << msg
        effective_warning_handler&.execute(msg)

        nil
      end

      # Access arbitrary metadata.
      #
      # @param key [Symbol, String]
      # @return [Object, nil]
      def [](key)
        @metadata[key]
      end

      # Set arbitrary metadata.
      #
      # @param key [Symbol, String]
      # @param value [Object]
      # @return [Object]
      def []=(key, value)
        @metadata[key] = value
      end

      # Check if metadata key exists.
      #
      # @param key [Symbol, String]
      # @return [Boolean]
      def key?(key)
        @metadata.key?(key)
      end

      # Fetch metadata with default.
      #
      # @param key [Symbol, String]
      # @param default [Object]
      # @return [Object]
      def fetch(key, default = nil, &block)
        @metadata.fetch(key, default, &block)
      end

      # Validate required inputs.
      #
      # @raise [ArgumentError] if character or user is missing
      # @return [self]
      def validate!
        raise ArgumentError, "character is required" if @character.nil?
        raise ArgumentError, "user is required" if @user.nil?

        self
      end

      # Get effective history (ensure ChatHistory::Base).
      #
      # @return [ChatHistory::Base]
      def effective_history
        @history || ChatHistory.new
      end

      # Get effective preset (ensure Preset).
      #
      # @return [Preset]
      def effective_preset
        @preset || Preset.new
      end

      # Append a lore book.
      #
      # @param book [Lore::Book]
      # @return [self]
      def append_lore_book(book)
        @lore_books << book
        self
      end

      # Force activate World Info entries.
      #
      # @param activations [Array<Hash>]
      # @return [self]
      def force_world_info(activations)
        @forced_world_info_activations = Array(activations)
        self
      end

      private

      def effective_warning_handler
        return default_warning_handler if @warning_handler == :default
        return nil if @warning_handler.nil?

        @warning_handler
      end

      def default_warning_handler
        ->(msg) { $stderr.puts("WARN: #{msg}") }
      end
    end
  end
end
