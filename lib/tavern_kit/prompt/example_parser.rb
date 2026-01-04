# frozen_string_literal: true

require_relative "message"

module TavernKit
  module Prompt
    # Parses SillyTavern example dialogues (mes_example) into real user/assistant messages.
    #
    # Format (from ST docs):
    # - Blocks are separated by <START> markers
    # - Inside a block, lines starting with {{user}}: or {{char}}: begin a new message
    class ExampleParser
      USER_PREFIX_RE = /^\s*\{\{\s*user\s*\}\}\s*:\s*/i
      CHAR_PREFIX_RE = /^\s*\{\{\s*char\s*\}\}\s*:\s*/i
      START_RE = /^\s*<START>\s*$/i

      # @return [Array<Array<Prompt::Message>>] array of example blocks, each block is an array of messages
      def self.parse_blocks(text)
        return [] if text.nil? || text.to_s.strip.empty?

        lines = text.to_s.gsub("\r\n", "\n").gsub("\r", "\n").split("\n")

        blocks = []
        buf = []

        lines.each do |line|
          if line.match?(START_RE)
            blocks << buf unless buf.empty?
            buf = []
          else
            buf << line
          end
        end
        blocks << buf unless buf.empty?

        blocks.map { |block_lines| parse_block_lines(block_lines) }.reject(&:empty?)
      end

      def self.parse_block_lines(lines)
        messages = []
        current_role = nil
        current_content = +""

        flush = lambda do
          return if current_role.nil?

          messages << Message.new(role: current_role, content: current_content.rstrip)
          current_role = nil
          current_content = +""
        end

        lines.each do |line|
          if line.match?(USER_PREFIX_RE)
            flush.call
            current_role = :user
            current_content = line.sub(USER_PREFIX_RE, "")
            next
          end

          if line.match?(CHAR_PREFIX_RE)
            flush.call
            current_role = :assistant
            current_content = line.sub(CHAR_PREFIX_RE, "")
            next
          end

          # Ignore stray whitespace before the first marker.
          next if current_role.nil? && line.to_s.strip.empty?

          if current_role.nil?
            next
          else
            current_content << "\n" unless current_content.empty?
            current_content << line
          end
        end

        flush.call
        messages
      end

      private_class_method :parse_block_lines
    end
  end
end
