# frozen_string_literal: true

require_relative "middleware/base"

module TavernKit
  module Prompt
    # A composable middleware pipeline for prompt construction.
    #
    # The Pipeline manages an ordered stack of middlewares that process
    # a Context object. Each middleware can transform the context before
    # and after passing to subsequent middlewares.
    #
    # @example Using the default pipeline
    #   ctx = Context.new(character: char, user: user, user_message: "Hello!")
    #   Pipeline.default.call(ctx)
    #   ctx.plan  # => Prompt::Plan
    #
    # @example Customizing the pipeline
    #   pipeline = Pipeline.default.tap do |p|
    #     p.replace :lore, MyCustomLoreMiddleware
    #     p.insert_before :compilation, ValidationMiddleware
    #   end
    #
    # @example Building a pipeline from scratch
    #   pipeline = Pipeline.new do
    #     use Middleware::Hooks
    #     use Middleware::Lore
    #     use Middleware::Entries
    #     # ...
    #   end
    #
    class Pipeline
      include Enumerable

      # Entry representing a middleware in the pipeline.
      Entry = Data.define(:middleware, :options, :name)

      # Create the default ST-compatible pipeline.
      #
      # @return [Pipeline]
      def self.default
        new do
          use Middleware::Hooks, name: :hooks
          use Middleware::Lore, name: :lore
          use Middleware::Entries, name: :entries
          use Middleware::PinnedGroups, name: :pinned_groups
          use Middleware::Injection, name: :injection
          use Middleware::Compilation, name: :compilation
          use Middleware::MacroExpansion, name: :macro_expansion
          use Middleware::PlanAssembly, name: :plan_assembly
          use Middleware::Trimming, name: :trimming
        end
      end

      # Create a minimal pipeline (no middlewares).
      #
      # @return [Pipeline]
      def self.empty
        new
      end

      def initialize(&block)
        @entries = []
        @index = {}
        instance_eval(&block) if block
      end

      # Deep copy for safe modification.
      def initialize_copy(original)
        super
        @entries = original.instance_variable_get(:@entries).map(&:dup)
        @index = original.instance_variable_get(:@index).dup
      end

      # Add a middleware to the end of the pipeline.
      #
      # @param middleware [Class<Middleware::Base>] middleware class
      # @param name [Symbol, nil] name for later reference (auto-derived if nil)
      # @param options [Hash] options passed to middleware constructor
      # @return [self]
      def use(middleware, name: nil, **options)
        resolved_name = resolve_name(middleware, name)

        if @index.key?(resolved_name)
          raise ArgumentError, "Middleware name already registered: #{resolved_name}"
        end

        entry = Entry.new(middleware: middleware, options: options, name: resolved_name)
        @entries << entry
        @index[resolved_name] = @entries.size - 1
        self
      end

      # Replace a middleware by name.
      #
      # @param name [Symbol] name of middleware to replace
      # @param middleware [Class<Middleware::Base>] new middleware class
      # @param options [Hash] options for new middleware
      # @return [self]
      def replace(name, middleware, **options)
        idx = @index[name]
        raise ArgumentError, "Unknown middleware: #{name}" unless idx

        @entries[idx] = Entry.new(middleware: middleware, options: options, name: name)
        self
      end

      # Insert a middleware before another.
      #
      # @param before_name [Symbol] name of middleware to insert before
      # @param middleware [Class<Middleware::Base>] middleware class to insert
      # @param name [Symbol, nil] name for the new middleware
      # @param options [Hash] options for new middleware
      # @return [self]
      def insert_before(before_name, middleware, name: nil, **options)
        idx = @index[before_name]
        raise ArgumentError, "Unknown middleware: #{before_name}" unless idx

        resolved_name = resolve_name(middleware, name)
        if @index.key?(resolved_name)
          raise ArgumentError, "Middleware name already registered: #{resolved_name}"
        end

        entry = Entry.new(middleware: middleware, options: options, name: resolved_name)
        @entries.insert(idx, entry)
        reindex!
        self
      end

      # Insert a middleware after another.
      #
      # @param after_name [Symbol] name of middleware to insert after
      # @param middleware [Class<Middleware::Base>] middleware class to insert
      # @param name [Symbol, nil] name for the new middleware
      # @param options [Hash] options for new middleware
      # @return [self]
      def insert_after(after_name, middleware, name: nil, **options)
        idx = @index[after_name]
        raise ArgumentError, "Unknown middleware: #{after_name}" unless idx

        resolved_name = resolve_name(middleware, name)
        if @index.key?(resolved_name)
          raise ArgumentError, "Middleware name already registered: #{resolved_name}"
        end

        entry = Entry.new(middleware: middleware, options: options, name: resolved_name)
        @entries.insert(idx + 1, entry)
        reindex!
        self
      end

      # Remove a middleware by name.
      #
      # @param name [Symbol] name of middleware to remove
      # @return [self]
      def remove(name)
        idx = @index[name]
        raise ArgumentError, "Unknown middleware: #{name}" unless idx

        @entries.delete_at(idx)
        reindex!
        self
      end

      # Configure options for a middleware.
      #
      # @param name [Symbol] middleware name
      # @param options [Hash] options to merge
      # @return [self]
      def configure(name, **options)
        idx = @index[name]
        raise ArgumentError, "Unknown middleware: #{name}" unless idx

        entry = @entries[idx]
        @entries[idx] = Entry.new(
          middleware: entry.middleware,
          options: entry.options.merge(options),
          name: entry.name
        )
        self
      end

      # Execute the pipeline on a context.
      #
      # @param ctx [Context] the prompt context
      # @return [Context] the processed context
      def call(ctx)
        stack = build_stack
        stack.call(ctx)
        ctx
      end

      # Iterate over middleware entries.
      #
      # @yield [Entry]
      def each(&block)
        @entries.each(&block)
      end

      # @return [Integer] number of middlewares
      def size
        @entries.size
      end

      # @return [Boolean] true if no middlewares
      def empty?
        @entries.empty?
      end

      # @return [Array<Symbol>] list of middleware names in order
      def names
        @entries.map(&:name)
      end

      # Check if a middleware is registered.
      #
      # @param name [Symbol]
      # @return [Boolean]
      def has?(name)
        @index.key?(name)
      end

      # Get a middleware entry by name.
      #
      # @param name [Symbol]
      # @return [Entry, nil]
      def [](name)
        idx = @index[name]
        idx ? @entries[idx] : nil
      end

      private

      def resolve_name(middleware, name)
        return name if name

        if middleware.respond_to?(:middleware_name)
          middleware.middleware_name
        else
          middleware.name.split("::").last
            .gsub(/Middleware$/, "")
            .gsub(/([a-z])([A-Z])/, '\1_\2')
            .downcase
            .to_sym
        end
      end

      def reindex!
        @index.clear
        @entries.each_with_index do |entry, idx|
          @index[entry.name] = idx
        end
      end

      def build_stack
        # Terminal handler just returns the context
        app = ->(ctx) { ctx }

        # Build stack from last to first (so first middleware wraps the rest)
        @entries.reverse_each do |entry|
          app = entry.middleware.new(app, **entry.options)
        end

        app
      end
    end
  end
end
