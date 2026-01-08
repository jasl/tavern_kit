# frozen_string_literal: true

require "digest"
require_relative "base"

module TavernKit
  module Prompt
    module Middleware
      # Middleware that evaluates World Info (Lorebook) entries.
      #
      # This middleware:
      # - Loads character book and global lore books
      # - Builds scan buffer from history + user_message
      # - Evaluates keywords to find activated entries
      # - Applies token budget and priority selection
      # - Outputs a Lore::Result with outlets
      #
      class Lore < Base
        ST_DEFAULT_WORLD_INFO_DEPTH = 2
        ST_MAX_SCAN_MESSAGES = 100

        private

        def before(ctx)
          ctx.validate!

          # Initialize computed values
          preset = ctx.effective_preset
          history = ctx.effective_history
          user_message = ctx.user_message.to_s

          # Compute scan context values
          ctx.default_chat_depth = preset.world_info_depth.nil? ? ST_DEFAULT_WORLD_INFO_DEPTH : preset.world_info_depth.to_i
          ctx.chat_scan_messages = build_prompt_entry_scan_messages(ctx, history, user_message)
          ctx.turn_count = history.user_message_count + 1

          # Initialize variables store
          ctx.variables_store = resolve_variables_store(ctx)

          # Load and evaluate lore books
          books = load_books(ctx)
          return if books.empty? || books.none? { |b| b&.entries&.any? }

          scan_depth = effective_world_info_depth(books, ctx)
          ctx.scan_messages = build_scan_messages(ctx, history, user_message)
          ctx.scan_context = build_scan_context(ctx)
          ctx.scan_injects = build_world_info_scan_injects(ctx, history, user_message)

          lore_budget = compute_world_info_budget_tokens(ctx)

          engine = ctx.lore_engine || ::TavernKit::Lore::Engine.new(token_estimator: ctx.token_estimator)

          ctx.lore_result = engine.evaluate(
            books: books,
            scan_messages: ctx.scan_messages,
            scan_depth: scan_depth,
            scan_context: ctx.scan_context,
            scan_injects: ctx.scan_injects,
            token_budget: lore_budget,
            insertion_strategy: ctx.effective_preset.character_lore_insertion_strategy,
            generation_type: ctx.generation_type,
            message_count: history.size + 1,
            variables_store: ctx.variables_store,
            min_activations: ctx.effective_preset.world_info_min_activations,
            min_activations_depth_max: ctx.effective_preset.world_info_min_activations_depth_max,
            use_group_scoring: ctx.effective_preset.world_info_use_group_scoring,
            forced_activations: ctx.forced_world_info_activations
          )

          # One-shot behavior: clear forced activations after evaluation
          ctx.forced_world_info_activations = []

          # Extract outlets
          ctx.outlets = ctx.lore_result&.outlets || {}
        end

        def load_books(ctx)
          books = []

          # Load character book
          char_book = load_character_book(ctx)
          books << char_book if char_book

          # Add global lore books (coerce hashes to Lore::Book)
          if ctx.lore_books
            ctx.lore_books.each do |book|
              coerced = coerce_lore_book(ctx, book)
              books << coerced if coerced
            end
          end

          dedupe_books(books)
        end

        def dedupe_books(books)
          seen = {}
          Array(books).filter_map do |book|
            next if book.nil?

            sig = lore_book_signature(book)
            if sig
              next if seen[sig]

              seen[sig] = true
            end

            book
          end
        end

        def lore_book_signature(book)
          raw = book.respond_to?(:raw) ? book.raw : nil
          return nil unless raw.is_a?(Hash)

          normalized = deep_sort_for_signature(raw)
          digest = Digest::SHA256.hexdigest(JSON.generate(normalized))
          "#{book.source}|#{digest}"
        rescue StandardError
          nil
        end

        def deep_sort_for_signature(value)
          case value
          when Hash
            value
              .to_h
              .sort_by { |k, _| k.to_s }
              .to_h { |k, v| [k.to_s, deep_sort_for_signature(v)] }
          when Array
            value.map { |v| deep_sort_for_signature(v) }
          else
            value
          end
        end

        def coerce_lore_book(ctx, book)
          return book if book.is_a?(::TavernKit::Lore::Book)
          return nil if book.nil?

          if book.is_a?(Hash)
            ::TavernKit::Lore::Book.from_hash(book, source: :global)
          elsif book.respond_to?(:to_hash)
            ::TavernKit::Lore::Book.from_hash(book.to_hash, source: :global)
          else
            book
          end
        rescue StandardError => e
          ctx.warn("Failed to load lore book: #{e.class}: #{e.message}")
          nil
        end

        def load_character_book(ctx)
          return nil unless ctx.character

          cb = ctx.character.data.character_book
          return nil unless cb.is_a?(Hash)

          ::TavernKit::Lore::Book.from_hash(cb, source: :character)
        rescue StandardError => e
          ctx.warn("Failed to load character book: #{e.class}: #{e.message}")
          nil
        end

        def resolve_variables_store(ctx)
          variables_input = ctx.macro_vars[:local_store] if ctx.macro_vars.is_a?(Hash)
          ::TavernKit::ChatVariables.wrap(variables_input)
        end

        def effective_world_info_depth(books, ctx)
          preset = ctx.effective_preset
          preset_depth = preset.world_info_depth

          if preset_depth.nil?
            max_book_depth = books.compact.map { |b| b.scan_depth.to_i }.max
            max_book_depth && max_book_depth > 0 ? max_book_depth : ST_DEFAULT_WORLD_INFO_DEPTH
          else
            preset_depth.to_i
          end
        end

        def build_scan_messages(ctx, history, user_message)
          preset = ctx.effective_preset

          current_msg = Message.new(
            role: :user,
            content: user_message.to_s,
            name: ctx.user&.name
          )
          # Only the tail matters for scanning; avoid materializing the full history.
          all = Array(history.last(ST_MAX_SCAN_MESSAGES)) + [current_msg]

          formatted = if preset.world_info_include_names
            all.map { |m| format_message_with_name(m, ctx) }
          else
            all.map(&:content)
          end

          formatted.map! { |s| s.to_s.strip }
          formatted.reverse.first(ST_MAX_SCAN_MESSAGES)
        end

        def build_prompt_entry_scan_messages(ctx, history, user_message)
          # Prompt-entry scanning ignores system messages; keep a rolling window of the most recent
          # non-system contents, without materializing the entire history.
          keep = ST_MAX_SCAN_MESSAGES - 1 # Reserve one slot for current user input
          tail = []

          history.each do |m|
            next if m.role == :system

            tail << m.content
            tail.shift while tail.length > keep
          end

          formatted = tail + [user_message.to_s]
          formatted.map! { |s| s.to_s.strip }

          formatted.reverse.first(ST_MAX_SCAN_MESSAGES)
        end

        def format_message_with_name(message, ctx)
          name = message.name.to_s.strip
          name = resolve_message_name(message, ctx) if name.empty?
          content = message.content.to_s

          name.empty? ? content : "#{name}: #{content}"
        end

        def resolve_message_name(message, ctx)
          case message.role
          when :user
            ctx.user&.name.to_s
          when :assistant
            ctx.character&.name.to_s
          else
            ""
          end
        end

        def build_scan_context(ctx)
          char = ctx.character
          user = ctx.user
          char_data = char&.data

          # Extract depth_prompt from extensions
          depth_prompt_text = nil
          if char_data&.extensions.is_a?(Hash)
            dp = char_data.extensions["depth_prompt"] || char_data.extensions[:depth_prompt]
            depth_prompt_text = dp["prompt"] || dp[:prompt] if dp.is_a?(Hash)
          end

          {
            char: char&.name.to_s,
            user: user&.name.to_s,
            group: ctx.group&.members&.map { |m| m.respond_to?(:name) ? m.name : m.to_s },
            generation_type: ctx.generation_type,
            # Scan context fields for matchCharacterX flags
            character_description: char_data&.description.to_s,
            character_personality: char_data&.personality.to_s,
            character_depth_prompt: depth_prompt_text.to_s,
            scenario: char_data&.scenario.to_s,
            creator_notes: char_data&.creator_notes.to_s,
            persona_description: user&.persona.to_s,
          }
        end

        def build_world_info_scan_injects(ctx, history, user_message)
          expander = ctx.expander || default_expander
          values = []

          if ctx.effective_preset.authors_note_allow_wi_scan
            authors_note = expand_world_info_scannable_authors_note(ctx, expander)
            values << authors_note if authors_note

            depth_prompt = expand_world_info_scannable_depth_prompt(ctx, expander)
            values << depth_prompt if depth_prompt
          end

          values.concat(build_injection_registry_scan_injects(ctx, history, user_message, expander: expander))
          values
        end

        def expand_world_info_scannable_authors_note(ctx, expander)
          return nil unless authors_note_active_for_world_info_scan?(ctx)

          template = ctx.effective_preset.authors_note.to_s
          return nil if template.strip.empty?

          content = expander.expand(template, build_expander_vars(ctx), allow_outlets: false)
          content = content.to_s.strip
          content.empty? ? nil : content
        end

        def authors_note_active_for_world_info_scan?(ctx)
          entry = ctx.effective_preset.effective_prompt_entries.find { |pe| pe.id.to_s == "authors_note" }
          return false unless entry&.enabled?
          return false unless entry.triggered_by?(ctx.generation_type)

          frequency = ctx.effective_preset.authors_note_frequency.to_i
          return false if frequency == 0

          turn_count = ctx.turn_count.to_i
          return false if turn_count.positive? && (turn_count % frequency != 0)

          true
        end

        def expand_world_info_scannable_depth_prompt(ctx, expander)
          template = character_depth_prompt_text(ctx)
          return nil if template.strip.empty?

          content = expander.expand(template, build_expander_vars(ctx), allow_outlets: false)
          content = content.to_s.strip
          content.empty? ? nil : content
        end

        def character_depth_prompt_text(ctx)
          extensions = ctx.character&.data&.extensions
          return "" unless extensions.is_a?(Hash)

          dp = extensions["depth_prompt"] || extensions[:depth_prompt]
          return "" unless dp.is_a?(Hash)

          (dp["prompt"] || dp[:prompt]).to_s
        end

        def build_injection_registry_scan_injects(ctx, history, user_message, expander:)
          return [] unless ctx.injection_registry && !ctx.injection_registry.empty?

          filter_ctx = build_injection_filter_context(ctx, history, user_message)

          values = []
          ctx.injection_registry.each do |inj|
            next unless inj.scan?
            next unless injection_filter_passes?(inj, filter_ctx, ctx)

            expanded = expander.expand(inj.content, build_expander_vars(ctx), allow_outlets: false)
            expanded = expanded.to_s.strip
            values << expanded unless expanded.empty?
          end

          values
        end

        def build_injection_filter_context(ctx, history, user_message)
          {
            character: ctx.character,
            user: ctx.user,
            preset: ctx.effective_preset,
            history_messages: history,
            user_message: user_message.to_s,
            generation_type: ctx.generation_type,
            group: ctx.group,
            macro_vars: ctx.macro_vars,
            outlets: ctx.outlets || {},
            lore_result: ctx.lore_result,
            chat_scan_messages: ctx.chat_scan_messages,
            default_chat_depth: ctx.default_chat_depth,
            turn_count: ctx.turn_count,
          }
        end

        def injection_filter_passes?(inj, filter_ctx, ctx)
          filter = inj&.filter
          return true unless filter.respond_to?(:call)

          ok = filter.arity == 0 ? filter.call : filter.call(filter_ctx)
          !!ok
        rescue StandardError => e
          ctx.warn("Injection filter error for #{inj&.id.inspect}: #{e.class}: #{e.message}")
          false
        end

        def compute_world_info_budget_tokens(ctx)
          preset = ctx.effective_preset

          # ST logic: budget = explicit budget OR (context_window - reserved_response)
          if preset.world_info_budget
            preset.world_info_budget.to_i
          elsif preset.context_window_tokens && preset.reserved_response_tokens
            [preset.context_window_tokens.to_i - preset.reserved_response_tokens.to_i, 0].max
          end
        end
      end
    end
  end
end
