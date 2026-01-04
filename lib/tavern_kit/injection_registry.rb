# frozen_string_literal: true

module TavernKit
  # A per-chat/per-builder registry for programmatic prompt injections.
  #
  # This mirrors SillyTavern's STscript `/inject` feature at the data-model level:
  # - register/remove by id
  # - overlapping id overwrites previous entry
  # - positions: before/after/chat/none
  # - options: depth/role/scan/filter/ephemeral
  #
  # NOTE: Filter evaluation, macro expansion, and actual prompt placement are handled
  # by the prompt pipeline, not by this registry.
  class InjectionRegistry
    Injection = Data.define(
      :id,
      :content,
      :position,
      :depth,
      :role,
      :scan,
      :filter,
      :ephemeral,
    ) do
      def scan?
        !!scan
      end

      def ephemeral?
        !!ephemeral
      end
    end

    include Enumerable

    POSITIONS = %i[before after chat none].freeze
    ROLES = %i[system user assistant].freeze

    def initialize
      @injections = {}
    end

    # Register (or replace) an injection by id.
    #
    # If content is an empty string, this behaves like ST `/inject` with no text:
    # the injection is removed.
    #
    # @param id [String, Symbol] injection id (required)
    # @param content [String] injection content
    # @param position [Symbol] one of POSITIONS
    # @param options [Hash] depth/role/scan/filter/ephemeral (strict types)
    # @return [String] normalized id
    def register(id:, content:, position:, **options)
      unless id.is_a?(String) || id.is_a?(Symbol)
        raise ArgumentError, "id must be a String or Symbol, got: #{id.class}"
      end
      id_str = id.to_s.strip
      raise ArgumentError, "id is required" if id_str.empty?

      unless content.is_a?(String)
        raise ArgumentError, "content must be a String, got: #{content.class}"
      end
      content_str = content
      if content_str.empty?
        remove(id: id_str)
        return id_str
      end

      unless position.is_a?(Symbol) && POSITIONS.include?(position)
        raise ArgumentError, "position must be one of #{POSITIONS.inspect}, got: #{position.inspect}"
      end
      pos = position

      depth = options.key?(:depth) ? options[:depth] : 4
      unless depth.is_a?(Integer) && depth >= 0
        raise ArgumentError, "depth must be a non-negative Integer, got: #{depth.inspect}"
      end

      role = options.key?(:role) ? options[:role] : :system
      unless role.is_a?(Symbol) && ROLES.include?(role)
        raise ArgumentError, "role must be one of #{ROLES.inspect}, got: #{role.inspect}"
      end

      scan = options.key?(:scan) ? options[:scan] : false
      unless scan == true || scan == false
        raise ArgumentError, "scan must be a Boolean, got: #{scan.class}"
      end

      ephemeral = options.key?(:ephemeral) ? options[:ephemeral] : false
      unless ephemeral == true || ephemeral == false
        raise ArgumentError, "ephemeral must be a Boolean, got: #{ephemeral.class}"
      end

      filter = options[:filter]
      if !filter.nil? && !filter.respond_to?(:call)
        raise ArgumentError, "filter must respond to #call"
      end

      @injections[id_str] = Injection.new(
        id: id_str,
        content: content_str,
        position: pos,
        depth: depth,
        role: role,
        scan: scan,
        filter: filter,
        ephemeral: ephemeral,
      )

      id_str
    end

    # Remove an injection by id.
    #
    # @param id [String, Symbol]
    # @return [Injection, nil] removed injection
    def remove(id:)
      @injections.delete(id.to_s)
    end

    def [](id)
      @injections[id.to_s]
    end

    def ids
      @injections.keys.sort
    end

    def each
      return enum_for(:each) unless block_given?

      ids.each do |id|
        yield @injections.fetch(id)
      end
    end

    def size
      @injections.size
    end

    def empty?
      @injections.empty?
    end

    # Returns ids of injections marked ephemeral.
    # Builder uses this to prune after a build.
    def ephemeral_ids
      @injections.select { |_, inj| inj.ephemeral? }.keys
    end

    # Deep-ish copy suitable for independent use.
    def dup
      copy = self.class.new
      copy.instance_variable_set(:@injections, @injections.transform_values(&:dup))
      copy
    end

    private
  end
end
