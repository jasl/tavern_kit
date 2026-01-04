# frozen_string_literal: true

require "json"

module TavernKit
  # Context template settings for Story String assembly.
  #
  # Based on SillyTavern's power-user.js context settings, this class provides
  # configuration for building the story string (character/scenario/persona context)
  # and chat separators.
  #
  # The Story String is a Handlebars-like template that assembles character information.
  # Common fields include:
  # - `{{system}}` - system prompt
  # - `{{description}}` - character description
  # - `{{personality}}` - character personality
  # - `{{scenario}}` - scenario text
  # - `{{persona}}` - user persona
  # - `{{wiBefore}}` / `{{loreBefore}}` - world info before character defs
  # - `{{wiAfter}}` / `{{loreAfter}}` - world info after character defs
  # - `{{anchorBefore}}` / `{{anchorAfter}}` - anchors for injection positions
  # - `{{mesExamples}}` / `{{mesExamplesRaw}}` - example messages
  #
  # @example Basic usage
  #   context = TavernKit::ContextTemplate.new(
  #     story_string: "{{description}}\n{{personality}}\n{{scenario}}",
  #     chat_start: "[Start]",
  #     example_separator: "***"
  #   )
  class ContextTemplate
    # Story string position types (matches ST's extension_prompt_types)
    module Position
      # Insert at the end of the main prompt region
      IN_PROMPT = :in_prompt
      # Insert in chat history at specified depth
      IN_CHAT = :in_chat
      # Insert at the start of the main prompt region
      BEFORE_PROMPT = :before_prompt

      ALL = [IN_PROMPT, IN_CHAT, BEFORE_PROMPT].freeze

      def self.coerce(value)
        return IN_PROMPT if value.nil?

        # Handle numeric values from ST
        case value
        when 0, "0"
          return IN_PROMPT
        when 1, "1"
          return IN_CHAT
        when 2, "2"
          return BEFORE_PROMPT
        end

        sym = value.to_s.downcase.gsub("-", "_").to_sym
        ALL.include?(sym) ? sym : IN_PROMPT
      end
    end

    # Story string role types for in-chat injection
    module Role
      SYSTEM = :system
      USER = :user
      ASSISTANT = :assistant

      ALL = [SYSTEM, USER, ASSISTANT].freeze

      def self.coerce(value)
        return SYSTEM if value.nil?

        # Handle numeric values from ST (extension_prompt_roles)
        case value
        when 0, "0"
          return SYSTEM
        when 1, "1"
          return USER
        when 2, "2"
          return ASSISTANT
        end

        sym = value.to_s.downcase.to_sym
        ALL.include?(sym) ? sym : SYSTEM
      end
    end

    # Default story string template (matches ST's defaultStoryString)
    DEFAULT_STORY_STRING = <<~TEMPLATE.chomp
      {{#if system}}{{system}}
      {{/if}}{{#if description}}{{description}}
      {{/if}}{{#if personality}}{{char}}'s personality: {{personality}}
      {{/if}}{{#if scenario}}Scenario: {{scenario}}
      {{/if}}{{#if persona}}{{persona}}
      {{/if}}
    TEMPLATE

    # Default example separator (matches ST's defaultExampleSeparator)
    DEFAULT_EXAMPLE_SEPARATOR = "***"

    # Default chat start (matches ST's defaultChatStart)
    DEFAULT_CHAT_START = "***"

    # Default settings
    DEFAULTS = {
      preset: "Default",
      story_string: DEFAULT_STORY_STRING,
      chat_start: DEFAULT_CHAT_START,
      example_separator: DEFAULT_EXAMPLE_SEPARATOR,
      use_stop_strings: true,
      names_as_stop_strings: true,
      story_string_position: Position::IN_PROMPT,
      story_string_role: Role::SYSTEM,
      story_string_depth: 1,
    }.freeze

    # @return [String] preset name
    attr_reader :preset

    # @return [String] story string Handlebars-like template
    attr_reader :story_string

    # @return [String] chat start marker
    attr_reader :chat_start

    # @return [String] example dialogue separator
    attr_reader :example_separator

    # @return [Boolean] whether to use stop strings
    attr_reader :use_stop_strings

    # @return [Boolean] whether to use names as stop strings
    attr_reader :names_as_stop_strings

    # @return [Symbol] story string position (:in_prompt, :in_chat, :before_prompt)
    attr_reader :story_string_position

    # @return [Symbol] story string role for in-chat injection (:system, :user, :assistant)
    attr_reader :story_string_role

    # @return [Integer] story string depth for in-chat injection
    attr_reader :story_string_depth

    def initialize(**opts)
      opts = DEFAULTS.merge(opts.compact)

      @preset = opts[:preset].to_s
      @story_string = opts[:story_string].to_s
      @chat_start = opts[:chat_start].to_s
      @example_separator = opts[:example_separator].to_s
      @use_stop_strings = opts[:use_stop_strings].nil? ? true : !!opts[:use_stop_strings]
      @names_as_stop_strings = opts[:names_as_stop_strings].nil? ? true : !!opts[:names_as_stop_strings]
      @story_string_position = Position.coerce(opts[:story_string_position])
      @story_string_role = Role.coerce(opts[:story_string_role])
      @story_string_depth = [opts[:story_string_depth].to_i, 0].max
    end

    # Render the story string template with the provided params.
    #
    # Uses a simple Handlebars-like syntax:
    # - `{{field}}` → value or empty string
    # - `{{#if field}}...{{/if}}` → conditional block
    # - `{{#unless field}}...{{/unless}}` → negative conditional
    #
    # @param params [Hash] template parameters
    # @option params [String] :system system prompt
    # @option params [String] :description character description
    # @option params [String] :personality character personality
    # @option params [String] :scenario scenario text
    # @option params [String] :persona user persona
    # @option params [String] :char character name
    # @option params [String] :user user name
    # @option params [String] :wiBefore world info before
    # @option params [String] :wiAfter world info after
    # @option params [String] :loreBefore world info before (alias)
    # @option params [String] :loreAfter world info after (alias)
    # @option params [String] :anchorBefore anchor before
    # @option params [String] :anchorAfter anchor after
    # @option params [String] :mesExamples formatted example messages
    # @option params [String] :mesExamplesRaw raw example messages
    # @return [String] rendered story string
    def render(params = {})
      # Normalize keys to strings for consistent access
      p = params.transform_keys(&:to_s)

      # Start with the story string template
      result = @story_string.dup

      # Process {{#if field}}...{{/if}} blocks
      result = process_conditionals(result, p)

      # Process {{#unless field}}...{{/unless}} blocks
      result = process_unless_blocks(result, p)

      # Replace simple {{field}} macros
      result = replace_fields(result, p)

      # Ensure trailing newline (ST behavior)
      result = result.rstrip + "\n" unless result.empty?

      result
    end

    # Get stopping strings based on context settings.
    #
    # @param user_name [String] user name
    # @param char_name [String] character name
    # @return [Array<String>] array of stop strings
    def stopping_strings(user_name: "User", char_name: "Assistant")
      result = []

      if @names_as_stop_strings
        result << "\n#{char_name}:"
        result << "\n#{user_name}:"
      end

      result.compact.reject(&:empty?)
    end

    # Create a new ContextTemplate with modified settings.
    #
    # @param opts [Hash] settings to override
    # @return [ContextTemplate] new instance with merged settings
    def with(**opts)
      self.class.new(**to_h.merge(opts))
    end

    # Convert to a Hash representation.
    #
    # @return [Hash]
    def to_h
      {
        preset: @preset,
        story_string: @story_string,
        chat_start: @chat_start,
        example_separator: @example_separator,
        use_stop_strings: @use_stop_strings,
        names_as_stop_strings: @names_as_stop_strings,
        story_string_position: @story_string_position,
        story_string_role: @story_string_role,
        story_string_depth: @story_string_depth,
      }
    end

    # Load from a SillyTavern context preset JSON.
    #
    # @param hash [Hash] parsed JSON
    # @return [ContextTemplate]
    def self.from_st_json(hash)
      return new if hash.nil? || !hash.is_a?(Hash)

      h = Utils.deep_symbolize_keys(hash)
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
    # @return [ContextTemplate] new instance
    def self.load(json_string)
      data = JSON.parse(json_string, symbolize_names: true)
      new(**data)
    end

    # Load from a JSON file.
    #
    # @param path [String] file path
    # @return [ContextTemplate] new instance
    def self.load_from_file(path)
      load(File.read(path))
    end

    private

    # Process {{#if field}}content{{/if}} blocks
    def process_conditionals(template, params)
      # Match {{#if field}}...{{/if}} (non-greedy, handles nested)
      template.gsub(/\{\{#if\s+(\w+)\}\}(.*?)\{\{\/if\}\}/m) do |_match|
        field = Regexp.last_match(1)
        content = Regexp.last_match(2)

        value = params[field]
        # truthy check: non-nil, non-empty string
        if truthy?(value)
          # Recursively process nested conditionals
          process_conditionals(content, params)
        else
          ""
        end
      end
    end

    # Process {{#unless field}}content{{/unless}} blocks
    def process_unless_blocks(template, params)
      template.gsub(/\{\{#unless\s+(\w+)\}\}(.*?)\{\{\/unless\}\}/m) do |_match|
        field = Regexp.last_match(1)
        content = Regexp.last_match(2)

        value = params[field]
        # truthy check: non-nil, non-empty string
        if truthy?(value)
          ""
        else
          process_unless_blocks(content, params)
        end
      end
    end

    # Replace {{field}} macros with values
    def replace_fields(template, params)
      template.gsub(/\{\{(\w+)\}\}/) do |_match|
        field = Regexp.last_match(1)
        params[field].to_s
      end
    end

    def truthy?(value)
      return false if value.nil?
      return false if value.is_a?(String) && value.strip.empty?
      return false if value == false

      true
    end
  end
end
