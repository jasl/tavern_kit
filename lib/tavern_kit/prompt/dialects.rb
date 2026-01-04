# frozen_string_literal: true

require "digest"
require "json"

module TavernKit
  module Prompt
    # Dialect converters for transforming prompt messages to various LLM provider formats.
    #
    # Based on SillyTavern's prompt-converters.js, this module provides converters for:
    # - OpenAI Chat Completion API format (default)
    # - Anthropic Messages API format
    # - Plain text completion format
    #
    # @example Using dialects via Plan
    #   plan.to_messages(dialect: :openai)    # => [{role:, content:}]
    #   plan.to_messages(dialect: :anthropic) # => {messages:, system:}
    #   plan.to_messages(dialect: :text)      # => "System: ...\nuser: ...\nassistant:"
    #
    module Dialects
      # Supported dialect identifiers
      SUPPORTED = %i[
        openai
        anthropic
        cohere
        google
        ai21
        mistral
        xai
        text
      ].freeze

      # Default placeholder for empty message arrays (matches ST behavior)
      PLACEHOLDER = "..."

      PromptNames = Data.define(:user_name, :char_name, :group_names) do
        def initialize(user_name: nil, char_name: nil, group_names: nil)
          if !user_name.nil? && !user_name.is_a?(String)
            raise ArgumentError, "user_name must be a String (or nil), got: #{user_name.class}"
          end
          if !char_name.nil? && !char_name.is_a?(String)
            raise ArgumentError, "char_name must be a String (or nil), got: #{char_name.class}"
          end
          if !group_names.nil?
            unless group_names.is_a?(Array) && group_names.all? { |n| n.is_a?(String) }
              raise ArgumentError, "group_names must be an Array<String> (or nil), got: #{group_names.class}"
            end
          end

          super(user_name: user_name, char_name: char_name, group_names: (group_names || []))
        end

        def starts_with_group_name?(text)
          t = text.to_s
          group_names.any? do |name|
            n = name.to_s
            next false if n.strip.empty?

            t.start_with?("#{n}: ") || t.start_with?("#{n}:")
          end
        end
      end

      def self.coerce_names(value)
        return PromptNames.new if value.nil?
        return value if value.is_a?(PromptNames)

        if value.is_a?(Hash)
          sym = Utils.deep_symbolize_keys(value)
          return PromptNames.new(
            user_name: sym[:user_name],
            char_name: sym[:char_name],
            group_names: sym[:group_names],
          )
        end

        raise ArgumentError, "names must be a Dialects::PromptNames, Hash, or nil, got: #{value.class}"
      end

      def self.coerce_messages(messages)
        unless messages.is_a?(Array)
          raise ArgumentError, "messages must be an Array, got: #{messages.class}"
        end

        messages.map { |m| coerce_one_message(m) }
      end

      def self.coerce_one_message(message)
        case message
        when Message
          { role: message.role.to_s, content: message.content, name: message.name }
        when Hash
          # Normalize keys to symbols for internal use (deep to cover tool_calls and content blocks).
          sym = Utils.deep_symbolize_keys(message)

          role = if sym.key?(:role)
            sym[:role]
          elsif sym.key?(:Role)
            sym[:Role]
          end
          content = sym.key?(:content) ? sym[:content] : sym[:Content]
          name = sym.key?(:name) ? sym[:name] : sym[:Name]

          role_str = role.to_s
          raise ArgumentError, "message role is required" if role_str.strip.empty?

          sym[:role] = role_str
          sym[:content] = content
          sym[:name] = name
          sym
        else
          raise ArgumentError, "message must be a Prompt::Message or Hash, got: #{message.class}"
        end
      end

      def self.deep_dup(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), acc| acc[k] = deep_dup(v) }
        when Array
          obj.map { |v| deep_dup(v) }
        when String
          obj.dup
        else
          obj
        end
      end

      def self.try_parse_json(value)
        return value if value.is_a?(Hash) || value.is_a?(Array)

        s = value.to_s
        return value if s.strip.empty?

        JSON.parse(s)
      rescue JSON::ParserError
        value
      end

      class << self
        # Convert messages to the specified dialect format.
        #
        # @param messages [Array<Message>] array of Message objects
        # @param dialect [Symbol] target dialect (:openai, :anthropic, :text)
        # @return [Array<Hash>, Hash, String] formatted output for the dialect
        # @raise [ArgumentError] if dialect is not supported
        def convert(messages, dialect:, **opts)
          dialect_sym = dialect.to_sym
          unless SUPPORTED.include?(dialect_sym)
            raise ArgumentError, "Unknown dialect: #{dialect.inspect}. Supported: #{SUPPORTED.join(", ")}"
          end

          case dialect_sym
          when :openai
            OpenAI.convert(messages, **opts)
          when :anthropic
            Anthropic.convert(messages, **opts)
          when :cohere
            Cohere.convert(messages, **opts)
          when :google
            Google.convert(messages, **opts)
          when :ai21
            AI21.convert(messages, **opts)
          when :mistral
            Mistral.convert(messages, **opts)
          when :xai
            XAI.convert(messages, **opts)
          when :text
            Text.convert(messages, **opts)
          end
        end
      end

      # OpenAI Chat Completion API format.
      #
      # Produces: `[{role: "system"|"user"|"assistant", content: "..."}]`
      #
      # This is the standard format used by OpenAI, Azure OpenAI, and many
      # OpenAI-compatible APIs (Groq, Together, Fireworks, etc.).
      #
      module OpenAI
        class << self
          # Convert messages to OpenAI format.
          #
          # @param messages [Array<Message>] array of Message objects
          # @return [Array<Hash>] array of {role:, content:} hashes
          def convert(messages, **_opts)
            normalized = Dialects.coerce_messages(messages)

            normalized.map do |m|
              out = { role: m[:role].to_s, content: m[:content].nil? ? "" : m[:content] }

              name = m[:name].to_s
              out[:name] = name unless name.empty?

              # Preserve additional OpenAI-compatible fields when present.
              out[:tool_calls] = m[:tool_calls] if m.key?(:tool_calls)
              out[:tool_call_id] = m[:tool_call_id] if m.key?(:tool_call_id)
              out[:prefix] = m[:prefix] if m.key?(:prefix)

              out
            end
          end
        end
      end

      # Anthropic Messages API format.
      #
      # Produces:
      # ```ruby
      # {
      #   messages: [{role: "user"|"assistant", content: [{type: "text", text: "..."}]}],
      #   system: [{type: "text", text: "..."}]
      # }
      # ```
      #
      # Key behaviors (matching SillyTavern's convertClaudeMessages):
      # - Leading system messages are extracted to `system` array
      # - Remaining system messages are converted to user role
      # - Content is always an array of content blocks
      # - Consecutive same-role messages are merged
      # - Empty message arrays get a placeholder user message
      #
      module Anthropic
        class << self
          # Convert messages to Anthropic format.
          #
          # @param messages [Array<Message>] array of Message objects
          # @return [Hash] {messages: Array, system: Array}
          def convert(messages, assistant_prefill: nil, use_sys_prompt: true, use_tools: true, names: nil, **_opts)
            working = Dialects.coerce_messages(messages)
            names = Dialects.coerce_names(names)

            system_blocks = []

            if use_sys_prompt
              # Collect all the system messages up until the first instance of a non-system message,
              # and then remove them from the messages array.
              i = 0
              while i < working.length
                break if working[i][:role] != "system"

                if names.user_name && working[i][:name].to_s == "example_user"
                  prefix = "#{names.user_name}: "
                  working[i][:content] = "#{prefix}#{working[i][:content]}" unless working[i][:content].to_s.start_with?(prefix)
                end
                if names.char_name && working[i][:name].to_s == "example_assistant"
                  prefix = "#{names.char_name}: "
                  unless working[i][:content].to_s.start_with?(prefix) || names.starts_with_group_name?(working[i][:content])
                    working[i][:content] = "#{prefix}#{working[i][:content]}"
                  end
                end

                system_blocks << { type: "text", text: working[i][:content].to_s }
                i += 1
              end

              working.shift(i)

              # Prevent erroring out if the messages array is empty.
              if working.empty?
                working.unshift({ role: "user", content: PLACEHOLDER })
              end
            end

            # Now replace all further messages that have the role 'system' with the role 'user'. (or all if we're not using one)
            working.each do |msg|
              # Tool call conversions (best-effort parity)
              if msg[:role] == "assistant" && use_tools && msg[:tool_calls].is_a?(Array)
                msg[:content] = Array(msg[:tool_calls]).map do |tc|
                  fn = tc.is_a?(Hash) ? tc[:function] : nil
                  fn = fn.is_a?(Hash) ? fn : {}
                  args = fn[:arguments]
                  {
                    type: "tool_use",
                    id: tc.is_a?(Hash) ? tc[:id].to_s : "",
                    name: fn[:name].to_s,
                    input: Dialects.try_parse_json(args),
                  }
                end
              end

              if msg[:role] == "tool"
                msg[:role] = "user"
                if use_tools
                  msg[:content] = [{
                    type: "tool_result",
                    tool_use_id: msg[:tool_call_id].to_s,
                    content: msg[:content].to_s,
                  }]
                end
              end

              if msg[:role] == "system"
                if names.user_name && msg[:name].to_s == "example_user"
                  prefix = "#{names.user_name}: "
                  msg[:content] = "#{prefix}#{msg[:content]}" unless msg[:content].to_s.start_with?(prefix)
                end
                if names.char_name && msg[:name].to_s == "example_assistant"
                  prefix = "#{names.char_name}: "
                  unless msg[:content].to_s.start_with?(prefix) || names.starts_with_group_name?(msg[:content])
                    msg[:content] = "#{prefix}#{msg[:content]}"
                  end
                end

                msg[:role] = "user"
                msg.delete(:name)
              end

              # Convert everything to an array of blocks (text/tool).
              if msg[:content].is_a?(Array)
                msg[:content] = msg[:content].map do |part|
                  part_hash = part.is_a?(Hash) ? part.dup : { type: "text", text: part.to_s }
                  if part_hash[:type].to_s == "text"
                    part_hash[:text] = part_hash[:text].to_s
                    part_hash[:text] = "\u200b" if part_hash[:text].empty?
                  end
                  part_hash
                end
              elsif use_tools && msg[:content].is_a?(Array) # no-op; already handled
              else
                text = msg[:content].to_s
                if msg[:name] && !msg[:name].to_s.empty?
                  name_prefix = "#{msg[:name]}: "
                  text = "#{name_prefix}#{text}" unless text.start_with?(name_prefix)
                end
                text = "\u200b" if text.empty?
                msg[:content] = [{ type: "text", text: text }]
                msg.delete(:name)
              end

              # Remove offending properties
              msg.delete(:tool_calls)
              msg.delete(:tool_call_id)
            end

            # Assistant prefill (ST: append last assistant message when prefilling)
            prefill = assistant_prefill.to_s
            if !prefill.empty?
              working << {
                role: "assistant",
                content: [{ type: "text", text: prefill.rstrip }],
              }
            end

            # Since the messaging endpoint only supports user assistant roles in turns, we have to merge messages with the same role if they follow each other
            merged = []
            working.each do |msg|
              if merged.any? && merged.last[:role] == msg[:role]
                merged.last[:content].concat(msg[:content])
              else
                merged << msg
              end
            end

            # Optionally degrade tool blocks to text for providers/settings that don't support tools.
            unless use_tools
              merged.each do |msg|
                msg[:content].each do |part|
                  next unless part.is_a?(Hash)

                  case part[:type].to_s
                  when "tool_use"
                    input = part[:input]
                    part.replace(type: "text", text: input.is_a?(String) ? input : input.to_json)
                  when "tool_result"
                    part.replace(type: "text", text: part[:content].to_s)
                  end
                end
              end
            end

            { messages: merged, system: system_blocks }
          end
        end
      end

      # Cohere prompt format.
      #
      # Mirrors ST's convertCohereMessages at a high level.
      # Produces: `{ chat_history: [...] }`
      module Cohere
        class << self
          def convert(messages, names: nil, **_opts)
            working = Dialects.coerce_messages(messages)
            names = Dialects.coerce_names(names)

            if working.empty?
              working.unshift({ role: "user", content: PLACEHOLDER })
            end

            i = 0
            while i < working.length
              msg = working[i]

                # Tool calls require an assistant primer.
                if msg[:tool_calls].is_a?(Array)
                  if i.positive? && working[i - 1][:role].to_s == "assistant"
                    msg[:content] = working[i - 1][:content]
                    working.delete_at(i - 1)
                    i -= 1
                  else
                    fn_names = Array(msg[:tool_calls]).map do |tc|
                      fn = tc.is_a?(Hash) ? tc[:function] : nil
                      fn.is_a?(Hash) ? fn[:name] : nil
                    end.compact.map(&:to_s)
                    msg[:content] = "I'm going to call a tool for that: #{fn_names.join(", ")}"
                  end
                end

              # Names are not supported: move into content.
              if msg[:name]
                name = msg[:name].to_s
                if msg[:role].to_s == "system" && name == "example_assistant"
                  if names.char_name && !msg[:content].to_s.start_with?("#{names.char_name}: ") && !names.starts_with_group_name?(msg[:content])
                    msg[:content] = "#{names.char_name}: #{msg[:content]}"
                  end
                elsif msg[:role].to_s == "system" && name == "example_user"
                  if names.user_name && !msg[:content].to_s.start_with?("#{names.user_name}: ")
                    msg[:content] = "#{names.user_name}: #{msg[:content]}"
                  end
                elsif msg[:role].to_s != "system"
                  prefix = "#{name}: "
                  msg[:content] = "#{prefix}#{msg[:content]}" unless msg[:content].to_s.start_with?(prefix)
                end
                msg.delete(:name)
              end

              i += 1
            end

            { chat_history: working }
          end
        end
      end

      # Google MakerSuite / Gemini prompt format.
      #
      # Mirrors ST's convertGooglePrompt at a high level.
      # Produces: `{ contents: [...], system_instruction: { parts: [...] } }`
      module Google
        class << self
          def convert(messages, model:, use_sys_prompt: false, names: nil, **_opts)
            working = Dialects.coerce_messages(messages)
            names = Dialects.coerce_names(names)

            sys_prompt = []
            if use_sys_prompt
              while working.length > 1 && working.first[:role].to_s == "system"
                msg = working.first
                if names.user_name && msg[:name].to_s == "example_user"
                  prefix = "#{names.user_name}: "
                  msg[:content] = "#{prefix}#{msg[:content]}" unless msg[:content].to_s.start_with?(prefix)
                end
                if names.char_name && msg[:name].to_s == "example_assistant"
                  prefix = "#{names.char_name}: "
                  unless msg[:content].to_s.start_with?(prefix) || names.starts_with_group_name?(msg[:content])
                    msg[:content] = "#{prefix}#{msg[:content]}"
                  end
                end

                sys_prompt << msg[:content].to_s
                working.shift
              end
            end

            system_instruction = { parts: sys_prompt.map { |text| { text: text } } }
            tool_name_map = {}
            contents = []

            working.each_with_index do |message, index|
              role = message[:role].to_s
              role = "user" if %w[system tool].include?(role)
              role = "model" if role == "assistant"

              content_parts = message[:content]
              unless content_parts.is_a?(Array)
                has_tool_calls = message[:tool_calls].is_a?(Array) && !message[:tool_calls].empty?
                has_tool_call_id = message[:tool_call_id].is_a?(String) && !message[:tool_call_id].empty?

                content_parts = if has_tool_calls
                  [{ type: "tool_calls", tool_calls: message[:tool_calls] }]
                elsif has_tool_call_id
                  [{ type: "tool_call_id", tool_call_id: message[:tool_call_id], content: message[:content].to_s }]
                else
                  [{ type: "text", text: message[:content].to_s }]
                end
              end

              if message[:name]
                msg_name = message[:name].to_s
                content_parts.each do |part|
                  next unless part.is_a?(Hash) && part[:type].to_s == "text"

                  text = part[:text].to_s
                  if msg_name == "example_user"
                    if names.user_name && !text.start_with?("#{names.user_name}: ")
                      text = "#{names.user_name}: #{text}"
                    end
                  elsif msg_name == "example_assistant"
                    if names.char_name && !text.start_with?("#{names.char_name}: ") && !names.starts_with_group_name?(text)
                      text = "#{names.char_name}: #{text}"
                    end
                  else
                    prefix = "#{msg_name}: "
                    text = "#{prefix}#{text}" unless text.start_with?(prefix)
                  end
                  part[:text] = text
                end
              end

              parts = []
              content_parts.each do |part|
                part = part.is_a?(Hash) ? part : { type: "text", text: part.to_s }
                type = part[:type].to_s

                if type == "text"
                  parts << { text: part[:text].to_s }
                  next
                end

                if type == "tool_call_id"
                  id = part[:tool_call_id].to_s
                  name = tool_name_map[id] || "unknown"
                  parts << {
                    functionResponse: {
                      name: name,
                      response: { name: name, content: part[:content].to_s },
                    },
                  }
                  next
                end

                  if type == "tool_calls"
                    Array(part[:tool_calls]).each do |tc|
                      fn = tc.is_a?(Hash) ? tc[:function] : nil
                      fn = fn.is_a?(Hash) ? fn : {}
                      fn_name = fn[:name].to_s
                      fn_args = fn[:arguments]
                      parts << {
                        functionCall: {
                          name: fn_name,
                          args: Dialects.try_parse_json(fn_args) || fn_args,
                        },
                      }
                      tool_name_map[tc.is_a?(Hash) ? tc[:id].to_s : ""] = fn_name
                    end
                    next
                  end

                  # Inline data URLs (images/audio/video)
                  if %w[image_url video_url audio_url].include?(type)
                    url_obj = part[type.to_sym]
                    url = url_obj.is_a?(Hash) ? url_obj[:url] : nil
                    next unless url.to_s.start_with?("data:")

                    header, base64_data = url.to_s.split(",", 2)
                    mime = header[/data:([^;]+)/, 1] || (type == "image_url" ? "image/png" : type == "video_url" ? "video/mp4" : "audio/mpeg")
                    parts << { inlineData: { mimeType: mime, data: base64_data.to_s } }
                    next
                  end
              end

              # Gemini 3 migration signature marker
              if model.to_s.match?(/gemini-3/)
                skip_sig = "skip_thought_signature_validator"
                parts.select { |p| p.key?(:functionCall) }.each { |p| p[:thoughtSignature] = skip_sig }
                if model.to_s.match?(/-image/) && role == "model"
                  parts.select { |p| p.key?(:text) || p.key?(:inlineData) }.each { |p| p[:thoughtSignature] = skip_sig }
                end
              end

              if index.positive? && role == contents.last&.dig(:role)
                parts.each do |p|
                  if p.key?(:text)
                    existing = contents.last[:parts].find { |pp| pp.key?(:text) }
                    if existing
                      existing[:text] = "#{existing[:text]}\n\n#{p[:text]}"
                    else
                      contents.last[:parts] << p
                    end
                  else
                    contents.last[:parts] << p
                  end
                end
              else
                contents << { role: role, parts: parts }
              end
            end

            { contents: contents, system_instruction: system_instruction }
          end
        end
      end

      # AI21 prompt format.
      #
      # Mirrors ST's convertAI21Messages at a high level.
      # Produces: an array of role-tagged messages with system prompt squash + role merges.
      module AI21
        class << self
          def convert(messages, names: nil, **_opts)
            working = Dialects.coerce_messages(messages)
            names = Dialects.coerce_names(names)

            system_prompt = +""
            i = 0
            while i < working.length
              break if working[i][:role].to_s != "system"

              if names.user_name && working[i][:name].to_s == "example_user"
                prefix = "#{names.user_name}: "
                working[i][:content] = "#{prefix}#{working[i][:content]}" unless working[i][:content].to_s.start_with?(prefix)
              end
              if names.char_name && working[i][:name].to_s == "example_assistant"
                prefix = "#{names.char_name}: "
                unless working[i][:content].to_s.start_with?(prefix) || names.starts_with_group_name?(working[i][:content])
                  working[i][:content] = "#{prefix}#{working[i][:content]}"
                end
              end

              system_prompt << "#{working[i][:content]}\n\n"
              i += 1
            end

            working.shift(i)
            working.unshift({ role: "user", content: PLACEHOLDER }) if working.empty?

            unless system_prompt.empty?
              working.unshift({ role: "system", content: system_prompt.strip })
            end

            working.each do |msg|
              next unless msg[:name]

              prefix = "#{msg[:name]}: "
              if msg[:role].to_s != "system" && !msg[:content].to_s.start_with?(prefix)
                msg[:content] = "#{prefix}#{msg[:content]}"
              end
              msg.delete(:name)
            end

            merged = []
            working.each do |msg|
              if merged.any? && merged.last[:role].to_s == msg[:role].to_s
                merged.last[:content] = "#{merged.last[:content]}\n\n#{msg[:content]}"
              else
                merged << { role: msg[:role].to_s, content: msg[:content].to_s }
              end
            end

            merged
          end
        end
      end

      # Mistral prompt format.
      #
      # Mirrors ST's convertMistralMessages at a high level.
      module Mistral
        class << self
          def convert(messages, enable_prefix: false, names: nil, **_opts)
            working = Dialects.coerce_messages(messages)
            names = Dialects.coerce_names(names)

            if enable_prefix && !working.empty? && working.last[:role].to_s == "assistant"
              working.last[:prefix] = true
            end

            sanitize_tool_id = lambda do |id|
              Digest::SHA512.hexdigest(id.to_s)[0, 9]
            end

            working.each do |msg|
              if msg[:tool_calls].is_a?(Array)
                msg[:tool_calls].each do |tool|
                  next unless tool.is_a?(Hash) && tool.key?(:id)

                  tool[:id] = sanitize_tool_id.call(tool[:id])
                end
              end

              if msg[:role].to_s == "tool" && msg[:tool_call_id]
                msg[:tool_call_id] = sanitize_tool_id.call(msg[:tool_call_id])
              end

              if msg[:role].to_s == "system" && msg[:name].to_s == "example_assistant"
                if names.char_name && !msg[:content].to_s.start_with?("#{names.char_name}: ") && !names.starts_with_group_name?(msg[:content])
                  msg[:content] = "#{names.char_name}: #{msg[:content]}"
                end
                msg.delete(:name)
              end

              if msg[:role].to_s == "system" && msg[:name].to_s == "example_user"
                if names.user_name && !msg[:content].to_s.start_with?("#{names.user_name}: ")
                  msg[:content] = "#{names.user_name}: #{msg[:content]}"
                end
                msg.delete(:name)
              end

              if msg[:name] && msg[:role].to_s != "system"
                prefix = "#{msg[:name]}: "
                msg[:content] = "#{prefix}#{msg[:content]}" unless msg[:content].to_s.start_with?(prefix)
                msg.delete(:name)
              end
            end

            # If user role message immediately follows a tool message, append it to the last user message.
            rerun = true
            while rerun
              rerun = false
              working.each_with_index do |msg, idx|
                next if idx >= working.length - 1
                next unless msg[:role].to_s == "tool" && working[idx + 1][:role].to_s == "user"

                last_user_idx = working[0...idx].rindex { |m| m[:role].to_s == "user" && !m[:content].to_s.empty? }
                next if last_user_idx.nil?

                working[last_user_idx][:content] = "#{working[last_user_idx][:content]}\n\n#{working[idx + 1][:content]}"
                working.delete_at(idx + 1)
                rerun = true
                break
              end
            end

            # If system role message immediately follows an assistant message, change its role to user
            (0...(working.length - 1)).each do |idx|
              if working[idx][:role].to_s == "assistant" && working[idx + 1][:role].to_s == "system"
                working[idx + 1][:role] = "user"
              end
            end

            working
          end
        end
      end

      # xAI prompt format.
      #
      # Mirrors ST's convertXAIMessages at a high level.
      module XAI
        class << self
          def convert(messages, names: nil, **_opts)
            working = Dialects.coerce_messages(messages)
            names = Dialects.coerce_names(names)

            working.each do |msg|
              next if msg[:name].to_s.empty?
              next if msg[:role].to_s == "user"

              rule = nil
              if msg[:role].to_s == "assistant" && names.char_name &&
                  !msg[:content].to_s.start_with?("#{names.char_name}: ") &&
                  !names.starts_with_group_name?(msg[:content])
                rule = :char
              elsif msg[:role].to_s == "system" && msg[:name].to_s == "example_assistant" && names.char_name &&
                  !msg[:content].to_s.start_with?("#{names.char_name}: ") &&
                  !names.starts_with_group_name?(msg[:content])
                rule = :char
              elsif msg[:role].to_s == "system" && msg[:name].to_s == "example_user" && names.user_name &&
                  !msg[:content].to_s.start_with?("#{names.user_name}: ")
                rule = :user
              end

              if rule == :char
                msg[:content] = "#{names.char_name}: #{msg[:content]}"
              elsif rule == :user
                msg[:content] = "#{names.user_name}: #{msg[:content]}"
              end

              msg.delete(:name)
            end

            working
          end
        end
      end

      # Plain text completion format.
      #
      # Produces a string like:
      # ```
      # System: You are a helpful assistant.
      # user: Hello!
      # assistant: Hi there!
      # assistant:
      # ```
      #
      # Used for non-chat completion APIs and legacy models.
      # Matches SillyTavern's convertTextCompletionPrompt behavior.
      #
      # @example Basic text output
      #   Text.convert(messages)
      #
      # @example With instruct mode
      #   Text.convert(messages, instruct: my_instruct, names: { user_name: "Alice", char_name: "Bob" })
      #
      # @example Get stop sequences
      #   result = Text.convert(messages, instruct: my_instruct)
      #   result[:prompt]          # => "..."
      #   result[:stop_sequences]  # => ["### Instruction:", "\nAlice:"]
      #
      module Text
        class << self
          # Convert messages to plain text format.
          #
          # @param messages [Array<Message>] array of Message objects
          # @param instruct [Instruct, nil] instruct mode settings for formatting
          # @param context_template [ContextTemplate, nil] context template settings
          # @param names [PromptNames, Hash, nil] name settings for stop sequences
          # @param include_assistant_suffix [Boolean] whether to add assistant suffix at end
          # @param assistant_prefill [String, nil] prefill text for assistant response
          # @return [Hash, String] { prompt: String, stop_sequences: Array<String> } when instruct provided, otherwise String
          def convert(messages, instruct: nil, context_template: nil, names: nil, include_assistant_suffix: true, assistant_prefill: nil, **_opts)
            normalized = Dialects.coerce_messages(messages)
            names = Dialects.coerce_names(names)

            user_name = names.user_name || "user"
            char_name = names.char_name || "assistant"

            # Determine if we should use instruct mode formatting
            use_instruct = instruct.is_a?(Instruct) && instruct.enabled

            if use_instruct
              prompt = format_instruct_messages(normalized, instruct, names, include_assistant_suffix, assistant_prefill)
              stop_sequences = build_stop_sequences(instruct, context_template, user_name, char_name)
              { prompt: prompt, stop_sequences: stop_sequences }
            else
              prompt = format_simple_messages(normalized, user_name, char_name, include_assistant_suffix, assistant_prefill)
              stop_sequences = build_simple_stop_sequences(context_template, user_name, char_name)
              { prompt: prompt, stop_sequences: stop_sequences }
            end
          end

          private

          def format_simple_messages(messages, user_name, char_name, include_assistant_suffix, assistant_prefill)
            lines = messages.map do |msg|
              role = msg[:role].to_s
              name = msg[:name].to_s

              prefix = if role == "system" && name.empty?
                "System"
              elsif role == "system" && !name.empty?
                name
              elsif role == "user"
                user_name
              elsif role == "assistant"
                char_name
              else
                role
              end

              "#{prefix}: #{msg[:content]}"
            end

            result = lines.join("\n")

            if include_assistant_suffix
              prefill = assistant_prefill.to_s
              if prefill.empty?
                result += "\n#{char_name}:"
              else
                result += "\n#{char_name}: #{prefill}"
              end
            end

            result
          end

          def format_instruct_messages(messages, instruct, names, include_assistant_suffix, assistant_prefill)
            user_name = names.user_name || "User"
            char_name = names.char_name || "Assistant"

            parts = []
            message_count = messages.length

            messages.each_with_index do |msg, index|
              role = msg[:role].to_s
              name = msg[:name].to_s
              content = msg[:content].to_s
              is_first = index.zero?
              is_last = index == message_count - 1
              is_user = role == "user"
              _is_assistant = role == "assistant" # Currently unused but kept for clarity
              is_system = role == "system"

              # Determine speaker name for the message
              speaker = if is_system
                name.empty? ? "System" : name
              elsif is_user
                name.empty? ? user_name : name
              else # assistant
                name.empty? ? char_name : name
              end

              # Determine sequence variant based on position
              force_sequence = nil
              force_sequence = :first if is_first
              force_sequence = :last if is_last && !include_assistant_suffix

              # Format the message with instruct sequences
              formatted = instruct.format_chat(
                name: speaker,
                message: content,
                is_user: is_user,
                is_narrator: is_system,
                user_name: user_name,
                char_name: char_name,
                force_sequence: force_sequence,
                in_group: !names.group_names.empty?,
              )

              parts << formatted
            end

            result = parts.join

            # Add assistant suffix/prefill
            if include_assistant_suffix
              output_seq = instruct.output_sequence
              separator = instruct.wrap ? "\n" : ""

              prefill = assistant_prefill.to_s
              if prefill.empty?
                result = result.rstrip + separator + output_seq
              else
                # Include prefill after the output sequence
                result = result.rstrip + separator + output_seq + separator + prefill
              end
            end

            result
          end

          def build_stop_sequences(instruct, context_template, user_name, char_name)
            sequences = []

            # Get instruct mode stop sequences
            if instruct.is_a?(Instruct) && instruct.enabled
              sequences.concat(instruct.stopping_sequences(user_name: user_name, char_name: char_name))
            end

            # Add context template stop sequences
            if context_template.is_a?(ContextTemplate)
              sequences.concat(context_template.stopping_strings(user_name: user_name, char_name: char_name))
            end

            sequences.uniq.reject(&:empty?)
          end

          def build_simple_stop_sequences(context_template, user_name, char_name)
            sequences = []

            # Default name-based stop sequences
            sequences << "\n#{user_name}:"
            sequences << "\n#{char_name}:"

            # Add context template stop sequences
            if context_template.is_a?(ContextTemplate)
              sequences.concat(context_template.stopping_strings(user_name: user_name, char_name: char_name))
            end

            sequences.uniq.reject(&:empty?)
          end
        end
      end
    end
  end
end
