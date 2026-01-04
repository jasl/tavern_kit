# frozen_string_literal: true

require "json"

module TavernKit
  # Instruct mode settings for text completion formatting.
  #
  # Based on SillyTavern's instruct-mode.js, this class provides configuration
  # for formatting chat messages in instruct-style prompts (e.g., Alpaca, Vicuna, ChatML).
  #
  # @example Basic usage
  #   instruct = TavernKit::Instruct.new(
  #     enabled: true,
  #     input_sequence: "### Instruction:",
  #     output_sequence: "### Response:",
  #     wrap: true
  #   )
  #
  # @example ChatML style
  #   instruct = TavernKit::Instruct.new(
  #     enabled: true,
  #     input_sequence: "<|im_start|>user",
  #     input_suffix: "<|im_end|>",
  #     output_sequence: "<|im_start|>assistant",
  #     output_suffix: "<|im_end|>",
  #     system_sequence: "<|im_start|>system",
  #     system_suffix: "<|im_end|>",
  #     stop_sequence: "<|im_end|>",
  #     wrap: true
  #   )
  class Instruct
    # Names behavior types (matches ST's names_behavior_types)
    module NamesBehavior
      # Never include names in formatted messages
      NONE = :none
      # Include names only in group chats or when avatar is forced
      FORCE = :force
      # Always include names in formatted messages
      ALWAYS = :always

      ALL = [NONE, FORCE, ALWAYS].freeze

      def self.coerce(value)
        return FORCE if value.nil?

        sym = value.to_s.downcase.to_sym
        ALL.include?(sym) ? sym : FORCE
      end
    end

    # Default instruct mode settings (matches ST defaults in power-user.js)
    DEFAULTS = {
      enabled: false,
      preset: "Alpaca",
      input_sequence: "### Instruction:",
      input_suffix: "",
      output_sequence: "### Response:",
      output_suffix: "",
      system_sequence: "",
      system_suffix: "",
      last_system_sequence: "",
      first_input_sequence: "",
      first_output_sequence: "",
      last_input_sequence: "",
      last_output_sequence: "",
      story_string_prefix: "",
      story_string_suffix: "",
      stop_sequence: "",
      wrap: true,
      macro: true,
      names_behavior: NamesBehavior::FORCE,
      activation_regex: "",
      bind_to_context: false,
      user_alignment_message: "",
      system_same_as_user: false,
      sequences_as_stop_strings: true,
      skip_examples: false,
    }.freeze

    # @return [Boolean] whether instruct mode is enabled
    attr_reader :enabled

    # @return [String] preset name
    attr_reader :preset

    # @return [String] sequence before user/input messages
    attr_reader :input_sequence

    # @return [String] suffix after user/input messages
    attr_reader :input_suffix

    # @return [String] sequence before assistant/output messages
    attr_reader :output_sequence

    # @return [String] suffix after assistant/output messages
    attr_reader :output_suffix

    # @return [String] sequence before system messages
    attr_reader :system_sequence

    # @return [String] suffix after system messages
    attr_reader :system_suffix

    # @return [String] sequence before the last system message
    attr_reader :last_system_sequence

    # @return [String] sequence before the first input message
    attr_reader :first_input_sequence

    # @return [String] sequence before the first output message
    attr_reader :first_output_sequence

    # @return [String] sequence before the last input message
    attr_reader :last_input_sequence

    # @return [String] sequence before the last output message
    attr_reader :last_output_sequence

    # @return [String] prefix for story string (instruct mode)
    attr_reader :story_string_prefix

    # @return [String] suffix for story string (instruct mode)
    attr_reader :story_string_suffix

    # @return [String] stop sequence to terminate generation
    attr_reader :stop_sequence

    # @return [Boolean] whether to wrap sequences with newlines
    attr_reader :wrap

    # @return [Boolean] whether to expand macros in sequences
    attr_reader :macro

    # @return [Symbol] names behavior (:none, :force, :always)
    attr_reader :names_behavior

    # @return [String] regex for automatic instruct mode activation
    attr_reader :activation_regex

    # @return [Boolean] whether to bind instruct settings to context template
    attr_reader :bind_to_context

    # @return [String] user alignment message
    attr_reader :user_alignment_message

    # @return [Boolean] whether to use input sequence for system messages
    attr_reader :system_same_as_user

    # @return [Boolean] whether to use sequences as stop strings
    attr_reader :sequences_as_stop_strings

    # @return [Boolean] whether to skip formatting example messages
    attr_reader :skip_examples

    def initialize(**opts)
      opts = DEFAULTS.merge(opts.compact)

      @enabled = !!opts[:enabled]
      @preset = opts[:preset].to_s
      @input_sequence = opts[:input_sequence].to_s
      @input_suffix = opts[:input_suffix].to_s
      @output_sequence = opts[:output_sequence].to_s
      @output_suffix = opts[:output_suffix].to_s
      @system_sequence = opts[:system_sequence].to_s
      @system_suffix = opts[:system_suffix].to_s
      @last_system_sequence = opts[:last_system_sequence].to_s
      @first_input_sequence = opts[:first_input_sequence].to_s
      @first_output_sequence = opts[:first_output_sequence].to_s
      @last_input_sequence = opts[:last_input_sequence].to_s
      @last_output_sequence = opts[:last_output_sequence].to_s
      @story_string_prefix = opts[:story_string_prefix].to_s
      @story_string_suffix = opts[:story_string_suffix].to_s
      @stop_sequence = opts[:stop_sequence].to_s
      @wrap = opts[:wrap].nil? ? true : !!opts[:wrap]
      @macro = opts[:macro].nil? ? true : !!opts[:macro]
      @names_behavior = NamesBehavior.coerce(opts[:names_behavior])
      @activation_regex = opts[:activation_regex].to_s
      @bind_to_context = !!opts[:bind_to_context]
      @user_alignment_message = opts[:user_alignment_message].to_s
      @system_same_as_user = !!opts[:system_same_as_user]
      @sequences_as_stop_strings = opts[:sequences_as_stop_strings].nil? ? true : !!opts[:sequences_as_stop_strings]
      @skip_examples = !!opts[:skip_examples]
    end

    # Format a chat message according to instruct mode settings.
    #
    # Based on ST's formatInstructModeChat function.
    #
    # @param name [String] speaker name
    # @param message [String] message content
    # @param is_user [Boolean] whether this is a user message
    # @param is_narrator [Boolean] whether this is a narrator/system message
    # @param user_name [String] the user's name
    # @param char_name [String] the character's name
    # @param force_avatar [String, nil] forced avatar (for group chats)
    # @param force_sequence [Symbol, nil] force :first or :last sequence variant
    # @param in_group [Boolean] whether this is a group chat
    # @param macro_expander [#call, nil] optional macro expander proc
    # @return [String] formatted message
    def format_chat(
      name:,
      message:,
      is_user: false,
      is_narrator: false,
      user_name: "User",
      char_name: "Assistant",
      force_avatar: nil,
      force_sequence: nil,
      in_group: false,
      macro_expander: nil
    )
      # Determine if we should include names
      include_names = if is_narrator
        false
      elsif @names_behavior == NamesBehavior::ALWAYS
        true
      elsif @names_behavior == NamesBehavior::FORCE
        # Include names in group chats or when avatar is forced and not the user
        (in_group && name != user_name) || (force_avatar && name != user_name)
      else
        false
      end

      prefix = get_prefix(is_user: is_user, is_narrator: is_narrator, force_sequence: force_sequence)
      suffix = get_suffix(is_user: is_user, is_narrator: is_narrator)

      # Apply macro expansion if enabled and expander provided
      if @macro && macro_expander
        prefix = macro_expander.call(prefix)
        prefix = prefix.gsub(/\{\{name\}\}/i, name.to_s.empty? ? "System" : name.to_s)

        suffix = macro_expander.call(suffix)
        suffix = suffix.gsub(/\{\{name\}\}/i, name.to_s.empty? ? "System" : name.to_s)
      end

      # Default suffix to newline if wrap is enabled and suffix is empty
      suffix = "\n" if suffix.empty? && @wrap

      separator = @wrap ? "\n" : ""

      # Build the text array
      content = include_names && !name.to_s.empty? ? "#{name}: #{message}" : message
      text_array = [prefix, content + suffix].reject(&:empty?)

      text_array.join(separator)
    end

    # Format a story string according to instruct mode settings.
    #
    # Based on ST's formatInstructModeStoryString function.
    #
    # @param story_string [String] the story string content
    # @param in_chat_position [Boolean] whether the story string is in-chat position
    # @param macro_expander [#call, nil] optional macro expander proc
    # @return [String] formatted story string
    def format_story_string(story_string, in_chat_position: false, macro_expander: nil)
      return "" if story_string.to_s.empty?

      result = story_string.to_s

      # Only apply sequences if not in-chat position (it will be wrapped by message sequences instead)
      apply_sequences = !in_chat_position

      separator = @wrap ? "\n" : ""

      if apply_sequences && !@story_string_prefix.empty?
        prefix = @story_string_prefix
        if macro_expander
          prefix = macro_expander.call(prefix)
          prefix = prefix.gsub(/\{\{name\}\}/i, "System")
        end
        result = prefix + separator + result
      end

      if apply_sequences && !@story_string_suffix.empty?
        suffix = @story_string_suffix
        suffix = macro_expander.call(suffix) if macro_expander
        result = result + suffix
      end

      result
    end

    # Get stopping sequences for text completion.
    #
    # Based on ST's getInstructStoppingSequences function.
    #
    # @param user_name [String] user name for {{name}} substitution
    # @param char_name [String] character name for {{name}} substitution
    # @param macro_expander [#call, nil] optional macro expander proc
    # @return [Array<String>] array of stop strings
    def stopping_sequences(user_name: "User", char_name: "Assistant", macro_expander: nil)
      return [] unless @enabled

      result = []

      # Helper to add a sequence
      add_sequence = lambda do |sequence|
        return if sequence.nil? || sequence.to_s.strip.empty?

        seq = @wrap ? "\n#{sequence}" : sequence
        seq = macro_expander.call(seq) if @macro && macro_expander
        result << seq unless result.include?(seq)
      end

      # Always add the explicit stop sequence
      add_sequence.call(@stop_sequence)

      # Add sequences as stop strings if enabled
      if @sequences_as_stop_strings
        # Substitute {{name}} in sequences
        input_seq = @input_sequence.gsub(/\{\{name\}\}/i, user_name)
        output_seq = @output_sequence.gsub(/\{\{name\}\}/i, char_name)
        first_output_seq = @first_output_sequence.gsub(/\{\{name\}\}/i, char_name)
        last_output_seq = @last_output_sequence.gsub(/\{\{name\}\}/i, char_name)
        system_seq = @system_sequence.gsub(/\{\{name\}\}/i, "System")
        last_system_seq = @last_system_sequence.gsub(/\{\{name\}\}/i, "System")

        add_sequence.call(input_seq)
        add_sequence.call(output_seq)
        add_sequence.call(first_output_seq) unless first_output_seq.empty?
        add_sequence.call(last_output_seq) unless last_output_seq.empty?
        add_sequence.call(system_seq)
        add_sequence.call(last_system_seq) unless last_system_seq.empty?
      end

      result.compact.reject(&:empty?)
    end

    # Create a new Instruct with modified settings.
    #
    # @param opts [Hash] settings to override
    # @return [Instruct] new instance with merged settings
    def with(**opts)
      self.class.new(**to_h.merge(opts))
    end

    # Convert to a Hash representation.
    #
    # @return [Hash]
    def to_h
      {
        enabled: @enabled,
        preset: @preset,
        input_sequence: @input_sequence,
        input_suffix: @input_suffix,
        output_sequence: @output_sequence,
        output_suffix: @output_suffix,
        system_sequence: @system_sequence,
        system_suffix: @system_suffix,
        last_system_sequence: @last_system_sequence,
        first_input_sequence: @first_input_sequence,
        first_output_sequence: @first_output_sequence,
        last_input_sequence: @last_input_sequence,
        last_output_sequence: @last_output_sequence,
        story_string_prefix: @story_string_prefix,
        story_string_suffix: @story_string_suffix,
        stop_sequence: @stop_sequence,
        wrap: @wrap,
        macro: @macro,
        names_behavior: @names_behavior,
        activation_regex: @activation_regex,
        bind_to_context: @bind_to_context,
        user_alignment_message: @user_alignment_message,
        system_same_as_user: @system_same_as_user,
        sequences_as_stop_strings: @sequences_as_stop_strings,
        skip_examples: @skip_examples,
      }
    end

    # Load from a SillyTavern instruct preset JSON.
    #
    # @param hash [Hash] parsed JSON
    # @return [Instruct]
    def self.from_st_json(hash)
      return new if hash.nil? || !hash.is_a?(Hash)

      h = Utils.deep_symbolize_keys(hash)

      # Migration: separator_sequence => output_suffix (ST migration)
      if h.key?(:separator_sequence)
        h[:output_suffix] ||= h.delete(:separator_sequence)
      end

      # Migration: names/names_force_groups => names_behavior
      if h.key?(:names)
        h[:names_behavior] = if h[:names]
          NamesBehavior::ALWAYS
        elsif h[:names_force_groups]
          NamesBehavior::FORCE
        else
          NamesBehavior::NONE
        end
        h.delete(:names)
        h.delete(:names_force_groups)
      end

      new(**h)
    end

    # ========================================
    # Serialization / Persistence
    # ========================================

    # Serialize to a JSON string.
    #
    # @param pretty [Boolean] whether to pretty-print the JSON (default: false)
    # @return [String] JSON string
    def dump(pretty: false)
      pretty ? JSON.pretty_generate(to_h) : JSON.generate(to_h)
    end

    # Save to a JSON file.
    #
    # @param path [String] file path
    # @param pretty [Boolean] whether to pretty-print the JSON (default: true)
    # @return [self] for chaining
    def dump_to_file(path, pretty: true)
      File.write(path, dump(pretty: pretty))
      self
    end

    # Load from a JSON string.
    #
    # @param json_string [String] JSON string
    # @return [Instruct] new instance
    def self.load(json_string)
      data = JSON.parse(json_string, symbolize_names: true)
      new(**data)
    end

    # Load from a JSON file.
    #
    # @param path [String] file path
    # @return [Instruct] new instance
    def self.load_from_file(path)
      load(File.read(path))
    end

    private

    def get_prefix(is_user:, is_narrator:, force_sequence:)
      if is_narrator
        return @system_same_as_user ? @input_sequence : @system_sequence
      end

      if is_user
        case force_sequence
        when :first
          return @first_input_sequence.empty? ? @input_sequence : @first_input_sequence
        when :last
          return @last_input_sequence.empty? ? @input_sequence : @last_input_sequence
        else
          return @input_sequence
        end
      end

      # Assistant/output
      case force_sequence
      when :first
        @first_output_sequence.empty? ? @output_sequence : @first_output_sequence
      when :last
        @last_output_sequence.empty? ? @output_sequence : @last_output_sequence
      else
        @output_sequence
      end
    end

    def get_suffix(is_user:, is_narrator:)
      if is_narrator
        return @system_same_as_user ? @input_suffix : @system_suffix
      end

      is_user ? @input_suffix : @output_suffix
    end
  end
end
