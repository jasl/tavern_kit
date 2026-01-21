# frozen_string_literal: true

require_relative "utils"

module TavernKit
  # Group chat context for group-aware macros and prompts.
  #
  # Group chat state is session data (not part of CCv2/CCv3). It is used for:
  # - {{group}} / {{groupNotMuted}} / {{charIfNotGroup}} macro semantics
  # - {{notChar}} macro semantics (requires current_character)
  # - group_nudge_prompt activation (group chat detection)
  #
  # This object is intentionally small and immutable to keep Builder/MacroContext type-safe.
  class GroupContext
    attr_reader :members, :muted, :current_character, :string

    def initialize(members: [], muted: [], current_character: nil, string: nil)
      @members = Array(members).map(&:to_s).reject { |v| v.strip.empty? }.freeze
      @muted = Array(muted).map(&:to_s).reject { |v| v.strip.empty? }.freeze
      @current_character = current_character&.to_s
      @string = string&.to_s
      freeze
    end

    # Parse convenience for migrating older execute sites.
    #
    # @param value [GroupContext, Hash, Array<String>, String, nil]
    # @return [GroupContext, nil]
    def self.parse(value)
      case value
      when nil
        nil
      when GroupContext
        value
      when Hash
        from_hash(value)
      when Array
        from_members(value)
      when String
        from_string(value)
      else
        raise ArgumentError, "group context must be a GroupContext, Hash, Array, String, or nil; got: #{value.class}"
      end
    end

    def self.from_members(members, muted: [], current_character: nil)
      new(members: members, muted: muted, current_character: current_character, string: nil)
    end

    def self.from_string(string)
      s = string.to_s
      s = nil if s.strip.empty?
      new(members: [], muted: [], current_character: nil, string: s)
    end

    # @param hash [Hash] keys: members, muted/disabled_members, current_character/current, string
    def self.from_hash(hash)
      unless hash.is_a?(Hash)
        raise ArgumentError, "group context must be a Hash, got: #{hash.class}"
      end

      sym = Utils.deep_symbolize_keys(hash)

      members = Array(sym[:members]).map(&:to_s).reject { |v| v.strip.empty? }

      muted_input = if sym.key?(:muted)
        sym[:muted]
      elsif sym.key?(:disabled_members)
        sym[:disabled_members]
      elsif sym.key?(:muted_members)
        sym[:muted_members]
      end
      muted = Array(muted_input).map(&:to_s).reject { |v| v.strip.empty? }

      current_character = if sym.key?(:current_character)
        sym[:current_character]
      elsif sym.key?(:current)
        sym[:current]
      end

      string = sym[:string]

      new(
        members: members,
        muted: muted,
        current_character: current_character,
        string: string,
      )
    end

    def group_string(include_muted: true)
      explicit = @string
      if explicit && !explicit.strip.empty?
        return explicit
      end

      members = @members
      return "" if members.empty?

      list = if include_muted
        members
      else
        members.reject { |m| @muted.include?(m) }
      end

      list.join(", ")
    end

    def present?(include_muted: true)
      !group_string(include_muted: include_muted).to_s.strip.empty?
    end

    def current_character_or(fallback_name)
      fallback = fallback_name.to_s

      cur = @current_character
      cur = nil if cur.nil? || cur.strip.empty?
      return fallback if cur.nil?

      # If we have an explicit member list, the current character should refer
      # to a member name. Treat unknown/stale values (including the accidental
      # string "nil") as missing and fall back.
      if !@members.empty? && !@members.include?(cur)
        return fallback
      end

      cur
    end

    def to_h
      {
        members: @members.dup,
        muted: @muted.dup,
        current_character: @current_character,
        string: @string,
      }
    end
  end
end
