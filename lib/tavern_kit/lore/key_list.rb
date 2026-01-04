# frozen_string_literal: true

module TavernKit
  module Lore
    # Parses SillyTavern-style key lists.
    #
    # In the UI, keys are typically entered as comma-separated values.
    # Regex keys are JavaScript-style literals with `/` delimiters and may
    # contain commas inside the regex pattern.
    module KeyList
      module_function

      def parse(input)
        case input
        in nil
          []
        in Array
          input.map { |v| v.to_s.strip }.reject(&:empty?)
        else
          smart_split(input.to_s)
        end
      end

      # Split a comma-separated list while allowing commas inside JS regex
      # literals such as `/foo,bar/i`.
      def smart_split(str)
        s = str.to_s
        return [] if s.strip.empty?

        tokens = []
        buf = +""
        mode = :normal # :normal, :regex, :flags
        escape = false

        s.each_char do |ch|
          case mode
          when :normal
            if ch == ","
              push_token(tokens, buf)
              buf = +""
              next
            end

            # Start of a JS regex literal. We only treat it as such if the
            # token is currently empty/whitespace.
            mode = :regex if ch == "/" && buf.strip.empty?
            buf << ch
          when :regex
            buf << ch

            if escape
              escape = false
              next
            end

            if ch == "\\"
              escape = true
            elsif ch == "/"
              # End of regex pattern; flags follow until comma/end.
              mode = :flags
            end
          when :flags
            if ch == ","
              push_token(tokens, buf)
              buf = +""
              mode = :normal
              next
            end

            buf << ch
          else
            raise ParseError, "Internal error: unknown parser mode #{mode.inspect}"
          end
        end

        push_token(tokens, buf)
        tokens
      end

      def push_token(tokens, buf)
        token = buf.to_s.strip
        tokens << token unless token.empty?
      end

      private_class_method :smart_split, :push_token
    end
  end
end
