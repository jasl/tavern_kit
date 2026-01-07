# frozen_string_literal: true

require "json"
require "time"
require "date"

require_relative "../invocation"
require_relative "../invocation_syntax"
require_relative "../../macro_registry"
require_relative "../../prompt/example_parser"

module TavernKit
  module Macro
    module Packs
      # Built-in SillyTavern-compatible macro pack.
      #
      # This module exists to make TavernKit's macro system extensible:
      # - All default ST macros live in registries (introspectable + overrideable).
      # - Host apps can replace any macro by registering the same name in their own registry.
      module SillyTavern
        class << self
          # Preprocessing directives for ST `{{...}}` syntax that require regex-level context.
          #
          # Used by macro engines (V1/V2) before evaluation.
          #
          # Note: core ST directives like `{{trim}}` and `{{// ... }}` are implemented
          # directly in {Macro::V1::Engine} in ST order (because ordering affects behavior),
          # so this registry is intentionally empty by default. Host apps may add their own
          # preprocessing rules here.
          def pipeline_registry
            @pipeline_registry ||= begin
              MacroRegistry.new
            end
          end

          # Parsing rules for ST-style macro spellings.
          #
          # Used by macro engines (V1/V2) to normalize raw `{{...}}` content into a
          # canonical macro name + args payload.
          #
          # Host apps can customize keyword support by passing a modified syntax to
          # the engine (e.g., `invocation_syntax: Packs::SillyTavern.invocation_syntax.except(:time_utc)`).
          def invocation_syntax
            @invocation_syntax ||= begin
              s = InvocationSyntax.new

              s.register(:outlet, /\Aoutlet::(.+)\z/i, description: "Parse outlet::Name") do |m, _raw|
                ["outlet", m[1].to_s.strip]
              end

              s.register(:setvar, /\Asetvar::([^:]+)::(.*)\z/i, description: "Parse setvar::name::value") do |m, _raw|
                ["setvar", { name: m[1].to_s.strip, value: m[2].to_s }]
              end

              s.register(:var, /\Avar::([^:]+?)(?:::([\s\S]+))?\z/i, description: "Parse var::name or var::name::index") do |m, _raw|
                ["var", { name: m[1].to_s.strip, index: m[2] }]
              end

              s.register(:datetimeformat, /\Adatetimeformat\s+(.+)\z/i, description: "Parse datetimeformat <format>") do |m, _raw|
                ["datetimeformat", m[1].to_s]
              end

              s.register(:time_utc, /\Atime_utc([+-]\d+)\z/i, description: "Parse time_utc±N suffix form") do |m, _raw|
                ["time_utc", m[1].to_s]
              end

              s.register(:timediff, /\Atimediff::(.*?)::(.*?)\z/i, description: "Parse timediff::a::b") do |m, _raw|
                ["timediff", { a: m[1].to_s, b: m[2].to_s }]
              end

              s.register(:random, /\Arandom\s*::?\s*(.+)\z/i, description: "Parse random list forms") do |m, _raw|
                ["random", m[1].to_s]
              end

              s.register(:pick, /\Apick\s*::?\s*(.+)\z/i, description: "Parse pick list forms") do |m, _raw|
                ["pick", m[1].to_s]
              end

              s.register(:roll, /\Aroll[ :](.+)\z/i, description: "Parse roll:d20 / roll d20 forms") do |m, _raw|
                ["roll", m[1].to_s.strip]
              end

              s.register(:reverse, /\Areverse:(?!:)([\s\S]+)\z/i, description: "Parse reverse:<text>") do |m, _raw|
                ["reverse", m[1].to_s]
              end

              s.register(:banned, /\Abanned\s+\"(.*)\"\z/i, description: "Parse banned \"...\"") do |m, _raw|
                ["banned", m[1].to_s]
              end

              # Best-effort generic parsing for user-defined parameter macros.
              # Examples:
              # - foo::bar   => name: "foo", args: "bar"
              # - foo:bar    => name: "foo", args: "bar"
              # - foo bar    => name: "foo", args: "bar"
              s.register(:generic, /\A([a-z0-9_]+)(?:(::|:|\s+)([\s\S]+))\z/i, description: "Generic macro argument parsing") do |m, _raw|
                [m[1].to_s.downcase, m[3].to_s]
              end

              s
            end
          end

          # Macros that require build context (character/user/history/preset/group/input).
          #
          # Used by the prompt pipeline to populate the macro env.
          def builder_registry
            @builder_registry ||= begin
              r = MacroRegistry.new
              install_builder_macros!(r)
              r
            end
          end

          # Utility macros implemented by Macro::V1::Engine as ST-compatible built-ins.
          #
          # These are used as a *fallback* when the env does not define the macro.
          # The macros are defined here so they can be overridden, enumerated, and
          # reused by host apps.
          def utilities_registry
            @utilities_registry ||= begin
              r = MacroRegistry.new
              install_utilities_macros!(r)
              r
            end
          end

          # Install builder-context macros into a registry.
          def install_builder_macros!(registry)
            register_character_field_macros!(registry)
            register_group_macros!(registry)
            register_conversation_state_macros!(registry)
            register_identity_macros!(registry)
            register_instruct_macros!(registry)
            register_context_template_macros!(registry)
            register_authors_note_macros!(registry)
            registry
          end

          # Install expander utility macros into a registry.
          def install_utilities_macros!(registry)
            register_utility_macros!(registry)
            register_time_macros!(registry)
            register_randomization_macros!(registry)
            register_variable_macros!(registry)
            register_outlet_macro!(registry)
            registry
          end

          private

          def register_identity_macros!(registry)
            # ST behavior: `user` and `char` are assigned late so they can expand inside other
            # fields like description/persona/charPrompt (which may contain nested macros).
            registry.register("user", description: "User name") { |ctx| ctx&.user&.name.to_s }
            # CCv3: {{char}} must use nickname if present, otherwise name
            registry.register("char", description: "Character name (or nickname if set)") do |ctx|
              nickname = ctx&.card&.data&.nickname.to_s
              nickname.empty? ? ctx&.card&.data&.name.to_s : nickname
            end
          end

          def register_character_field_macros!(registry)
            registry.register("description", description: "Character description") { |ctx| ctx&.card&.data&.description.to_s }
            registry.register("scenario", description: "Scenario text") { |ctx| ctx&.card&.data&.scenario.to_s }
            registry.register("personality", description: "Character personality") { |ctx| ctx&.card&.data&.personality.to_s }
            registry.register("persona", description: "User persona text") { |ctx| ctx&.user&.persona_text.to_s }

            registry.register("charprompt", description: "Character system prompt") { |ctx| ctx&.card&.data&.system_prompt.to_s }
            registry.register("charinstruction", description: "Character post-history instructions") do |ctx|
              ctx&.card&.data&.post_history_instructions.to_s
            end
            registry.register("charjailbreak", description: "Alias for charInstruction") do |ctx|
              ctx&.card&.data&.post_history_instructions.to_s
            end

            registry.register("mesexamplesraw", description: "Raw mes_example") { |ctx| ctx&.card&.data&.mes_example.to_s }
            registry.register("mesexamples", description: "Formatted mes_example dialogue blocks") do |ctx|
              # ST behavior (parseMesExamples): preserve raw blocks, normalize <START> markers,
              # and add a trailing newline per block. Do not parse/normalize role lines.
              examples_str = ctx&.card&.data&.mes_example.to_s
              return "" if examples_str.strip.empty? || examples_str == "<START>"

              normalized = examples_str
              normalized = "<START>\n#{normalized.strip}" unless normalized.strip.start_with?("<START>")

              normalized
                .split(/<START>/i)
                .drop(1)
                .map { |block| "<START>\n#{block.strip}\n" }
                .join
            end

            registry.register("charversion", description: "Character version string") { |ctx| ctx&.card&.data&.character_version.to_s }
            registry.register("char_version", description: "Alias for charVersion") { |ctx| ctx&.card&.data&.character_version.to_s }

            registry.register("chardepthprompt", description: "Character depth prompt extension text") do |ctx|
              extensions = Utils.deep_stringify_keys(ctx&.card&.data&.extensions || {})
              depth_prompt = extensions["depth_prompt"]
              depth_prompt.is_a?(Hash) ? depth_prompt["prompt"].to_s : ""
            end

            registry.register("creatornotes", description: "Character creator notes") { |ctx| ctx&.card&.data&.creator_notes.to_s }
          end

          def register_group_macros!(registry)
            registry.register("group", description: "Group member list (or character name when not in a group)") do |ctx|
              group_str = group_string(ctx&.group, include_muted: true)
              group_context_present?(ctx&.group, group_str) ? group_str.to_s : ctx&.card&.data&.name.to_s
            end

            registry.register("groupnotmuted", description: "Group member list excluding muted entries") do |ctx|
              group_str = group_string(ctx&.group, include_muted: false)
              group_context_present?(ctx&.group, group_str) ? group_str.to_s : ctx&.card&.data&.name.to_s
            end

            registry.register("charifnotgroup", description: "Character name in single chats; group list in group chats") do |ctx|
              full = group_string(ctx&.group, include_muted: true)
              group_context_present?(ctx&.group, full) ? full.to_s : ctx&.card&.data&.name.to_s
            end

            registry.register("notchar", description: "Everyone except current character (user + other group members)") do |ctx|
              if !group_context_present?(ctx&.group)
                ctx&.user&.name.to_s
              else
                members = Array(ctx&.group&.members).map(&:to_s).reject { |v| v.strip.empty? }
                if members.empty?
                  ctx&.user&.name.to_s
                else
                  current = group_current_character(ctx)
                  others = members.reject { |name| name == current }
                  (others + [ctx&.user&.name.to_s]).reject { |v| v.to_s.strip.empty? }.join(", ")
                end
              end
            end
          end

          def register_conversation_state_macros!(registry)
            registry.register("input", description: "Current user input") { |ctx| ctx&.input.to_s }

            registry.register("maxprompt", description: "Max context size (tokens)") do |ctx|
              tokens = ctx&.preset&.context_window_tokens
              tokens.nil? ? "" : tokens.to_i
            end

            registry.register("lastmessage", description: "Last chat message (skips swipe-in-progress message when applicable)") do |ctx|
              messages = ctx&.history&.to_a || []
              idx = last_message_index(messages)
              idx.nil? ? "" : messages[idx].content.to_s
            end

            registry.register("lastusermessage", description: "Last user message (skips swipe-in-progress message when applicable)") do |ctx|
              messages = ctx&.history&.to_a || []
              idx = last_message_index(messages, filter: ->(m) { m.role == :user })
              idx.nil? ? "" : messages[idx].content.to_s
            end

            registry.register("lastcharmessage", description: "Last assistant message (skips swipe-in-progress message when applicable)") do |ctx|
              messages = ctx&.history&.to_a || []
              idx = last_message_index(messages, filter: ->(m) { m.role == :assistant })
              idx.nil? ? "" : messages[idx].content.to_s
            end

            registry.register("lastmessageid", description: "0-based ID of last message (empty when unavailable)") do |ctx|
              idx = last_message_index(ctx&.history&.to_a || [])
              idx.nil? ? "" : idx.to_s
            end

            registry.register("firstincludedmessageid", description: "First included message id (best-effort)") do |ctx|
              (ctx&.history&.to_a || []).empty? ? "" : "0"
            end

            registry.register("firstdisplayedmessageid", description: "First displayed message id (best-effort)") do |ctx|
              (ctx&.history&.to_a || []).empty? ? "" : "0"
            end

            registry.register("lastswipeid", description: "Number of swipes in the last message (best-effort)") do |ctx|
              msg = ctx&.history&.to_a&.last
              swipes = msg&.respond_to?(:swipes) ? msg.swipes : nil
              swipes.is_a?(Array) ? swipes.length.to_s : ""
            rescue StandardError
              ""
            end

            registry.register("currentswipeid", description: "1-based swipe index of the last message (best-effort)") do |ctx|
              msg = ctx&.history&.to_a&.last
              swipe_id = msg&.respond_to?(:swipe_id) ? msg.swipe_id : nil
              swipe_id.nil? ? "" : (swipe_id.to_i + 1).to_s
            rescue StandardError
              ""
            end

            registry.register("idle_duration", description: "Humanized time since last user message (default: just now)") do |ctx, inv|
              messages = ctx&.history&.to_a || []
              return "just now" if messages.empty?

              # ST behavior: find the last user message that precedes the most recent non-system message.
              take_next = false
              last_user = nil
              (messages.length - 1).downto(0) do |i|
                msg = messages[i]
                next if msg.role == :system

                if msg.role == :user && take_next
                  last_user = msg
                  break
                end

                take_next = true
              end

              ts = last_user&.respond_to?(:send_date) ? last_user.send_date : nil
              t = parse_st_timestamp(ts)
              return "just now" if t.nil?

              now = inv&.now || Time.now
              seconds = (now - t).to_f
              moment_humanize_duration(seconds, with_suffix: false)
            rescue StandardError
              "just now"
            end
            registry.register("model", description: "Active model name (if provided by host app)") { |_ctx| "" }
            registry.register("lastgenerationtype", description: "Last generation type (ST-style)") { |ctx| ctx&.generation_type.to_s }
            registry.register("ismobile", description: "Whether client is mobile (ST-style; default: false)") { |_ctx| "false" }
          end

          # Instruct-mode macros (ST getInstructMacros)
          def register_instruct_macros!(registry)
            # Story string prefix/suffix
            registry.register("instructstorystringprefix", description: "Instruct mode story string prefix") do |ctx|
              instruct_setting(ctx, :story_string_prefix)
            end

            registry.register("instructstorystringsuffix", description: "Instruct mode story string suffix") do |ctx|
              instruct_setting(ctx, :story_string_suffix)
            end

            # Input/user sequence
            registry.register("instructinput", description: "Instruct mode input/user sequence") do |ctx|
              instruct_setting(ctx, :input_sequence)
            end
            registry.register("instructuserprefix", description: "Alias for instructInput") do |ctx|
              instruct_setting(ctx, :input_sequence)
            end

            # Output/assistant sequence
            registry.register("instructoutput", description: "Instruct mode output/assistant sequence") do |ctx|
              instruct_setting(ctx, :output_sequence)
            end
            registry.register("instructassistantprefix", description: "Alias for instructOutput") do |ctx|
              instruct_setting(ctx, :output_sequence)
            end

            # System sequence
            registry.register("instructsystem", description: "Instruct mode system sequence") do |ctx|
              instruct_setting(ctx, :system_sequence)
            end
            registry.register("instructsystemprefix", description: "Alias for instructSystem") do |ctx|
              instruct_setting(ctx, :system_sequence)
            end

            # Suffixes
            registry.register("instructinputsuffix", description: "Instruct mode input suffix") do |ctx|
              instruct_setting(ctx, :input_suffix)
            end
            registry.register("instructusersuffix", description: "Alias for instructInputSuffix") do |ctx|
              instruct_setting(ctx, :input_suffix)
            end

            registry.register("instructoutputsuffix", description: "Instruct mode output suffix") do |ctx|
              instruct_setting(ctx, :output_suffix)
            end
            registry.register("instructassistantsuffix", description: "Alias for instructOutputSuffix") do |ctx|
              instruct_setting(ctx, :output_suffix)
            end

            registry.register("instructsystemsuffix", description: "Instruct mode system suffix") do |ctx|
              instruct_setting(ctx, :system_suffix)
            end

            # First/last variants
            registry.register("instructfirstoutput", description: "Instruct mode first output sequence") do |ctx|
              v = instruct_setting(ctx, :first_output_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :output_sequence) : v
            end
            registry.register("instructfirstassistantprefix", description: "Alias for instructFirstOutput") do |ctx|
              v = instruct_setting(ctx, :first_output_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :output_sequence) : v
            end

            registry.register("instructlastoutput", description: "Instruct mode last output sequence") do |ctx|
              v = instruct_setting(ctx, :last_output_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :output_sequence) : v
            end
            registry.register("instructlastassistantprefix", description: "Alias for instructLastOutput") do |ctx|
              v = instruct_setting(ctx, :last_output_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :output_sequence) : v
            end

            registry.register("instructfirstinput", description: "Instruct mode first input sequence") do |ctx|
              v = instruct_setting(ctx, :first_input_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :input_sequence) : v
            end
            registry.register("instructfirstuserprefix", description: "Alias for instructFirstInput") do |ctx|
              v = instruct_setting(ctx, :first_input_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :input_sequence) : v
            end

            registry.register("instructlastinput", description: "Instruct mode last input sequence") do |ctx|
              v = instruct_setting(ctx, :last_input_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :input_sequence) : v
            end
            registry.register("instructlastuserprefix", description: "Alias for instructLastInput") do |ctx|
              v = instruct_setting(ctx, :last_input_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :input_sequence) : v
            end

            registry.register("instructlastsystem", description: "Instruct mode last system sequence") do |ctx|
              v = instruct_setting(ctx, :last_system_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :system_sequence) : v
            end
            registry.register("instructlastsystemprefix", description: "Alias for instructLastSystem") do |ctx|
              v = instruct_setting(ctx, :last_system_sequence)
              v.to_s.empty? ? instruct_setting(ctx, :system_sequence) : v
            end

            # System prompt macros
            registry.register("systemprompt", description: "System prompt (prefers character override when available)") do |ctx|
              char_prompt = ctx&.card&.data&.system_prompt.to_s
              prefer_char = ctx&.preset&.prefer_char_prompt
              main_prompt = ctx&.preset&.main_prompt.to_s

              if prefer_char && !char_prompt.empty?
                char_prompt
              else
                main_prompt
              end
            end

            registry.register("globalsystemprompt", description: "Global system prompt (ignores character override)") do |ctx|
              ctx&.preset&.main_prompt.to_s
            end
          end

          # Context template macros (ST getInstructMacros context section)
          def register_context_template_macros!(registry)
            registry.register("chatseparator", description: "Example dialogue separator") do |ctx|
              context_setting(ctx, :example_separator)
            end

            registry.register("chatstart", description: "Chat start marker") do |ctx|
              context_setting(ctx, :chat_start)
            end
          end

          def instruct_setting(ctx, key)
            return "" unless ctx&.preset

            instruct = ctx.preset.instruct || ctx.preset.effective_instruct
            return "" unless instruct

            instruct.public_send(key).to_s
          rescue StandardError
            ""
          end

          def context_setting(ctx, key)
            return "" unless ctx&.preset

            context = ctx.preset.context_template || ctx.preset.effective_context_template
            return "" unless context

            context.public_send(key).to_s
          rescue StandardError
            ""
          end

          # Author's Note macros (ST authors-note.js registerAuthorsNoteMacros)
          def register_authors_note_macros!(registry)
            # {{authorsNote}} - The contents of the current chat Author's Note
            registry.register("authorsnote", description: "The contents of the Author's Note") do |ctx|
              ctx&.preset&.authors_note.to_s
            end

            # {{charAuthorsNote}} - The contents of the Character Author's Note
            # In TavernKit, this comes from character card extensions.depth_prompt or a dedicated field
            registry.register("charauthorsnote", description: "The contents of the Character Author's Note") do |ctx|
              # Try to get from character card extensions
              extensions = Utils.deep_stringify_keys(ctx&.card&.data&.extensions || {})

              # Check for dedicated authors_note field in extensions
              char_an = extensions["authors_note"]
              return char_an.to_s if char_an.present?

              # Fallback: check for depth_prompt.prompt as some cards use this
              depth_prompt = extensions["depth_prompt"]
              depth_prompt.is_a?(Hash) ? depth_prompt["prompt"].to_s : ""
            end

            # {{defaultAuthorsNote}} - The contents of the Default Author's Note
            # In TavernKit, this is the same as the preset's authors_note since we don't have
            # separate default/chat-specific storage at the macro level
            registry.register("defaultauthorsnote", description: "The contents of the Default Author's Note") do |ctx|
              ctx&.preset&.authors_note.to_s
            end
          end

          def group_string(group, include_muted: true)
            return nil if group.nil?

            group.group_string(include_muted: include_muted)
          rescue StandardError
            ""
          end

          def group_context_present?(group, group_str = nil)
            return false if group.nil?

            s = group_str.nil? ? group_string(group, include_muted: true) : group_str
            !s.to_s.strip.empty?
          end

          def group_current_character(ctx)
            group = ctx&.group
            fallback = ctx&.card&.data&.name.to_s
            return fallback if group.nil?

            group.current_character_or(fallback)
          end

          # =========================
          # Utility macro handlers
          # =========================

          def register_utility_macros!(registry)
            registry.register("newline", description: "Newline character") { |_ctx, _inv| "\n" }
            registry.register("noop", description: "Empty string") { |_ctx, _inv| "" }
            registry.register("reverse", description: "Reverse helper (reverse:...)") { |_ctx, inv| inv.args.to_s.chars.reverse.join }
            registry.register("banned", description: "Remove macro content (no side effects)") { |_ctx, _inv| "" }

            # CCv3: {{comment:A}} - Remove content from output but display as inline comment in UI
            # Note: TavernKit treats this identically to // (no UI-side behavior)
            registry.register("comment", description: "Comment (removed from output)") { |_ctx, _inv| "" }

            # CCv3: {{hidden_key:A}} - Like comment but content is added to lorebook recursive scan buffer
            # The hidden key is stored in env[:hidden_keys] for the Lore::Engine to access
            registry.register("hidden_key", description: "Hidden key for lorebook recursive scanning") do |_ctx, inv|
              content = inv.args.to_s.strip
              unless content.empty?
                env = inv.env
                if env.is_a?(Hash)
                  env[:hidden_keys] ||= []
                  env[:hidden_keys] << content
                end
              end
              # Returns empty string (like comment)
              ""
            end
          end

          def register_time_macros!(registry)
            registry.register("date", description: "Current date") { |_ctx, inv| format_date(inv.now || Time.now) }
            registry.register("time", description: "Current time") { |_ctx, inv| format_time(inv.now || Time.now) }
            registry.register("weekday", description: "Day of week") { |_ctx, inv| (inv.now || Time.now).strftime("%A") }
            registry.register("isotime", description: "ISO time") { |_ctx, inv| (inv.now || Time.now).strftime("%H:%M") }
            registry.register("isodate", description: "ISO date") { |_ctx, inv| (inv.now || Time.now).strftime("%Y-%m-%d") }

            registry.register("datetimeformat", description: "Formatted date/time (moment-style tokens)") do |_ctx, inv|
              time = inv.now || Time.now
              format = inv.args.to_s
              time.strftime(moment_to_strftime(format))
            rescue StandardError
              ""
            end

            registry.register("time_utc", description: "Time with UTC offset (time_UTC±N)") do |_ctx, inv|
              offset_hours = inv.args.to_s.to_i
              time = (inv.now || Time.now).getutc + (offset_hours * 3600)
              format_time(time)
            rescue StandardError
              ""
            end

            registry.register("timediff", description: "Humanized time difference (timeDiff::a::b)") do |_ctx, inv|
              a = inv.args.is_a?(Hash) ? inv.args[:a] : nil
              b = inv.args.is_a?(Hash) ? inv.args[:b] : nil
              t1 = parse_st_timestamp(a)
              t2 = parse_st_timestamp(b)
              return "" if t1.nil? || t2.nil?

              seconds = (t1 - t2).to_f
              moment_humanize_duration(seconds, with_suffix: true)
            rescue StandardError
              ""
            end
          end

          def register_randomization_macros!(registry)
            registry.register("random", description: "Random selection (entropy-based)") do |_ctx, inv|
              list = inv.split_list
              list.empty? ? "" : list[inv.rng_or_new.rand(list.length)]
            end

            registry.register("pick", description: "Deterministic pick (content-seeded)") do |_ctx, inv|
              list = inv.split_list
              list.empty? ? "" : list[inv.pick_index(list.length)]
            end

            registry.register("roll", description: "Dice roll (roll:d20 / roll:2d6+1)") do |_ctx, inv|
              roll_dice(inv.args.to_s.strip, rng: inv.rng_or_new)
            end
          end

          def register_variable_macros!(registry)
            registry.register("setvar", description: "Set a variable (setvar::name::value)") do |_ctx, inv|
              payload = inv.args.is_a?(Hash) ? inv.args : {}
              name = payload[:name].to_s.strip
              value = payload[:value].to_s
              set_variable_store_value(inv.env, name, value)
              ""
            end

            registry.register("getvar", description: "Get a variable (getvar::name)") do |_ctx, inv|
              name, index = extract_variable_ref(inv.args)
              get_variable_store_value(inv.env, name, index)
            end

            registry.register("var", description: "Read a variable (var::name or var::name::index)") do |_ctx, inv|
              payload = inv.args.is_a?(Hash) ? inv.args : {}
              name = payload[:name].to_s.strip
              index = payload[:index]
              get_variable_store_value(inv.env, name, index)
            end

            registry.register("addvar", description: "Add to a variable (addvar::name::value)") do |_ctx, inv|
              name, value = extract_variable_pair(inv.args)
              add_variable_store_value(inv.env, name, value, store_key: :local_store)
              ""
            end

            registry.register("incvar", description: "Increment a variable (incvar::name)") do |_ctx, inv|
              name, _index = extract_variable_ref(inv.args)
              add_variable_store_value(inv.env, name, "1", store_key: :local_store)
            end

            registry.register("decvar", description: "Decrement a variable (decvar::name)") do |_ctx, inv|
              name, _index = extract_variable_ref(inv.args)
              add_variable_store_value(inv.env, name, "-1", store_key: :local_store)
            end

            registry.register("setglobalvar", description: "Set a global variable (setglobalvar::name::value)") do |_ctx, inv|
              name, value = extract_variable_pair(inv.args)
              set_variable_store_value(inv.env, name, value, store_key: :global_store)
              ""
            end

            registry.register("getglobalvar", description: "Get a global variable (getglobalvar::name)") do |_ctx, inv|
              name, index = extract_variable_ref(inv.args)
              get_variable_store_value(inv.env, name, index, store_key: :global_store)
            end

            registry.register("addglobalvar", description: "Add to a global variable (addglobalvar::name::value)") do |_ctx, inv|
              name, value = extract_variable_pair(inv.args)
              add_variable_store_value(inv.env, name, value, store_key: :global_store)
              ""
            end

            registry.register("incglobalvar", description: "Increment a global variable (incglobalvar::name)") do |_ctx, inv|
              name, _index = extract_variable_ref(inv.args)
              add_variable_store_value(inv.env, name, "1", store_key: :global_store)
            end

            registry.register("decglobalvar", description: "Decrement a global variable (decglobalvar::name)") do |_ctx, inv|
              name, _index = extract_variable_ref(inv.args)
              add_variable_store_value(inv.env, name, "-1", store_key: :global_store)
            end
          end

          def register_outlet_macro!(registry)
            registry.register("outlet", description: "World Info outlet content (outlet::Name)") do |_ctx, inv|
              return UNRESOLVED unless inv.allow_outlets

              outlet_name = inv.args.to_s.strip
              outlet_map = inv.outlets
              return UNRESOLVED unless outlet_map.is_a?(Hash)

              outlet_map.fetch(outlet_name, "").to_s
            rescue StandardError
              UNRESOLVED
            end
          end

          # =========================
          # Utility helpers
          # =========================

          def format_time(time)
            # ST "LT" format: h:mm A
            time.strftime("%-I:%M %p")
          end

          def format_date(time)
            # ST "LL" format: Month D, YYYY
            time.strftime("%B %-d, %Y")
          end

          def moment_to_strftime(format)
            return "%Y-%m-%d %H:%M:%S" if format.to_s.strip.empty?

            mapping = {
              "YYYY" => "%Y",
              "YY" => "%y",
              "MMMM" => "%B",
              "MMM" => "%b",
              "MM" => "%m",
              "M" => "%-m",
              "DD" => "%d",
              "D" => "%-d",
              "HH" => "%H",
              "H" => "%-H",
              "hh" => "%I",
              "h" => "%-I",
              "mm" => "%M",
              "m" => "%-M",
              "ss" => "%S",
              "s" => "%-S",
              "dddd" => "%A",
              "ddd" => "%a",
              "A" => "%p",
              "a" => "%P",
            }

            pattern = Regexp.union(mapping.keys.sort_by { |k| -k.length })
            format.gsub(pattern) { |token| mapping[token] }
          end

          def parse_st_timestamp(timestamp)
            return nil if timestamp.nil?

            case timestamp
            when Time
              return timestamp
            when DateTime
              return timestamp.to_time
            when Date
              return timestamp.to_time
            when Integer
              return Time.at(timestamp / 1000.0).utc
            when Float
              return Time.at(timestamp / 1000.0).utc
            end

            str = timestamp.to_s
            return nil if str.strip.empty?

            # Unix time in milliseconds (legacy)
            if str.match?(/\A\d+\z/)
              ms = str.to_i
              return Time.at(ms / 1000.0).utc
            end

            # ST "humanized" formats:
            # - 2024-7-12@01h31m37s
            # - 2024-6-5 @14h 56m 50s 682ms
            if (m = str.match(/\A(\d{4})-(\d{1,2})-(\d{1,2})@(\d{1,2})h(\d{1,2})m(\d{1,2})s\z/))
              return Time.utc(m[1].to_i, m[2].to_i, m[3].to_i, m[4].to_i, m[5].to_i, m[6].to_i)
            end

            if (m = str.match(/\A(\d{4})-(\d{1,2})-(\d{1,2}) @(\d{1,2})h (\d{1,2})m (\d{1,2})s (\d{1,3})ms\z/))
              ms = m[7].to_i
              return Time.utc(m[1].to_i, m[2].to_i, m[3].to_i, m[4].to_i, m[5].to_i, m[6].to_i) + (ms / 1000.0)
            end

            Time.parse(str)
          rescue StandardError
            nil
          end

          # Moment.js-like duration humanizer (best-effort, English only).
          #
          # ST reference:
          # - `moment.duration(now.diff(lastMessageDate)).humanize()` (no suffix)
          # - `moment.duration(time1.diff(time2)).humanize(true)` (with suffix)
          def moment_humanize_duration(seconds, with_suffix:)
            seconds = seconds.to_f
            future = seconds.positive?
            seconds = seconds.abs

            base = if seconds < 45
              "a few seconds"
            elsif seconds < 90
              "a minute"
            else
              minutes = (seconds / 60.0).round
              if minutes < 45
                "#{minutes} minutes"
              elsif minutes < 90
                "an hour"
              else
                hours = (seconds / 3600.0).round
                if hours < 22
                  "#{hours} hours"
                elsif hours < 36
                  "a day"
                else
                  days = (seconds / 86_400.0).round
                  if days < 26
                    "#{days} days"
                  elsif days < 45
                    "a month"
                  else
                    months = (seconds / 2_592_000.0).round # 30 days
                    if months < 11
                      "#{months} months"
                    else
                      years = (seconds / 31_536_000.0).round # 365 days
                      years <= 1 ? "a year" : "#{years} years"
                    end
                  end
                end
              end
            end

            return base unless with_suffix

            future ? "in #{base}" : "#{base} ago"
          rescue StandardError
            ""
          end

          def roll_dice(formula, rng:)
            return "" if formula.to_s.strip.empty?

            expr = formula.to_s.strip
            expr = "1d#{expr}" if expr.match?(/\A\d+\z/)

            total = 0
            terms = expr.scan(/[+-]?[^+-]+/)
            terms.each do |term|
              sign = term.start_with?("-") ? -1 : 1
              core = term.sub(/\A[+-]/, "")

              if (m = core.match(/\A(\d*)d(\d+)\z/i))
                count = m[1].to_s.empty? ? 1 : m[1].to_i
                sides = m[2].to_i
                return "" if count <= 0 || sides <= 0

                rolls = count.times.sum { rng.rand(1..sides) }
                total += sign * rolls
              elsif core.match?(/\A\d+\z/)
                total += sign * core.to_i
              else
                return ""
              end
            end

            total.to_s
          rescue StandardError
            ""
          end

          def set_variable_store_value(env, name, value, store_key: :local_store)
            return if name.to_s.strip.empty?

            store = variable_store_from_env(env, store_key)
            return unless store.respond_to?(:set)

            store.set(name.to_s, value.to_s)
          rescue StandardError
            nil
          end

          def get_variable_store_value(env, name, index = nil, store_key: :local_store)
            store = variable_store_from_env(env, store_key)
            return "" unless store.respond_to?(:get)

            key = name.to_s
            return "" if key.strip.empty?

            value = store.get(key)
            return "" if value.nil?

            if index.nil?
              format_variable_value(value)
            else
              indexed = index_variable_value(value, index)
              format_variable_value(indexed)
            end
          rescue StandardError
            ""
          end

          def add_variable_store_value(env, name, delta_or_value, store_key:)
            store = variable_store_from_env(env, store_key)
            return "" unless store.respond_to?(:get) && store.respond_to?(:set)

            key = name.to_s.strip
            return "" if key.empty?

            current = store.get(key)
            current = 0 if current.nil? || current.to_s.empty?

            # If the current value is a JSON array, push the raw delta/value and persist.
            begin
              parsed = JSON.parse(current.to_s)
              if parsed.is_a?(Array)
                parsed << delta_or_value
                store.set(key, JSON.generate(parsed))
                return parsed.map(&:to_s).join(",")
              end
            rescue JSON::ParserError
              # ignore and fall through
            end

            increment = parse_js_number(delta_or_value)
            current_num = parse_js_number(current)

            if increment.nil? || current_num.nil?
              new_value = current.to_s + delta_or_value.to_s
              store.set(key, new_value)
              return new_value.to_s
            end

            new_num = current_num + increment
            return "" if new_num.nan? || !new_num.finite?

            normalized = format_numeric(new_num)
            store.set(key, normalized)
            normalized
          rescue StandardError
            ""
          end

          def index_variable_value(value, index)
            v = value
            v = JSON.parse(v) if v.is_a?(String)

            idx = index.to_s
            num = parse_js_number(idx)

            if num.nil?
              if v.is_a?(Hash)
                return v[idx] if v.key?(idx)
                return v[idx.to_sym] if v.key?(idx.to_sym)
              end
              return nil
            end

            if v.is_a?(Array)
              i = js_integer_index(num)
              return nil if i.nil? || i.negative?
              return v[i]
            end

            if v.is_a?(Hash)
              key = js_number_key(num)
              return v[key] if v.key?(key)
              return v[key.to_sym] if v.key?(key.to_sym)
              return nil
            end

            if v.is_a?(String)
              i = js_integer_index(num)
              return nil if i.nil? || i.negative?
              return i < v.length ? v[i] : nil
            end

            nil
          rescue JSON::ParserError
            # If JSON parsing fails, fall back to JS-like direct indexing on the original value.
            v = value.to_s
            idx = index.to_s
            num = parse_js_number(idx)
            return nil if num.nil?

            i = js_integer_index(num)
            return nil if i.nil? || i.negative?
            i < v.length ? v[i] : nil
          end

          def format_variable_value(value)
            case value
            when nil
              ""
            when Hash, Array
              JSON.generate(value)
            when Numeric
              format_numeric(value)
            when String
              format_string_number(value)
            else
              value.to_s
            end
          end

          def format_numeric(num)
            if num.is_a?(Float) && num.finite? && (num % 1).zero?
              num.to_i.to_s
            else
              num.to_s
            end
          end

          def format_string_number(str)
            s = str.to_s
            return "" if s.strip.empty?

            num = Float(s)
            return s if num.nan?
            return format_numeric(num) if num.finite? && (num % 1).zero?

            num.to_s
          rescue ArgumentError, TypeError
            s
          end

          def parse_js_number(str)
            s = str.to_s
            s = "0" if s.strip.empty?

            num = Float(s)
            num.nan? ? nil : num
          rescue ArgumentError, TypeError
            nil
          end

          def js_integer_index(num)
            return nil unless num.finite?

            i = num.to_i
            i.to_f == num ? i : nil
          end

          def js_number_key(num)
            if num.finite? && (num % 1).zero?
              num.to_i.to_s
            else
              num.to_s
            end
          end

          def extract_variable_ref(args)
            case args
            when Hash
              [args[:name].to_s.strip, args[:index]]
            when String
              parts = args.split("::", 2)
              [parts[0].to_s.strip, parts[1]]
            else
              [args.to_s.strip, nil]
            end
          end

          def extract_variable_pair(args)
            case args
            when Hash
              [args[:name].to_s.strip, args[:value].to_s]
            when String
              parts = args.split("::", 2)
              [parts[0].to_s.strip, parts[1].to_s]
            else
              [args.to_s.strip, ""]
            end
          end

          def variable_store_from_env(env, store_key)
            return nil unless env.is_a?(Hash)

            env[store_key.to_sym]
          rescue StandardError
            nil
          end

          def last_message_index(messages, filter: nil)
            messages = Array(messages)
            return nil if messages.empty?

            (messages.length - 1).downto(0) do |i|
              msg = messages[i]
              next if swipe_in_progress?(msg)
              next if filter && !filter.call(msg)

              return i
            end

            nil
          rescue StandardError
            nil
          end

          def swipe_in_progress?(msg)
            swipes = msg&.respond_to?(:swipes) ? msg.swipes : nil
            swipe_id = msg&.respond_to?(:swipe_id) ? msg.swipe_id : nil
            return false unless swipes.is_a?(Array) && !swipe_id.nil?

            swipe_id.to_i >= swipes.length
          rescue StandardError
            false
          end
        end
      end
    end
  end
end
