# frozen_string_literal: true

require "test_helper"

module TavernKit
  module STCompatibility
    class TestMacrosLegacyAndVariables < Minitest::Test
      def test_original_macro_is_one_shot_in_overrides
        character = Character.create(
          name: "Alice",
          system_prompt: "OVERRIDE {{original}} {{original}}",
          mes_example: ""
        )
        user = User.new(name: "Bob")

        preset = Preset.new(
          main_prompt: "GLOBAL",
          post_history_instructions: "",
          prefer_char_prompt: true,
        )

        plan = TavernKit.build(character: character, user: user, preset: preset, message: "Hi")
        main = plan.messages.first.content

        assert_includes main, "OVERRIDE GLOBAL"
        refute_includes main, "GLOBAL GLOBAL"
      end

      def test_nested_macros_inside_macro_arguments_expand_before_post_env_macros
        character = Character.create(name: "Alice", mes_example: "")
        user = User.new(name: "Bob")
        expander = Macro::SillyTavernV1::Engine.new(rng: Random.new(0))

        preset = Preset.new(
          main_prompt: "X{{random::{{char}},x}}Y",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: user, preset: preset, expander: expander, message: "Hi")
        assert_equal "XAliceY", plan.messages.first.content
      end

      def test_pick_is_deterministic_when_pick_seed_is_provided
        character = Character.create(name: "Alice", mes_example: "")
        user = User.new(name: "Bob")

        preset = Preset.new(
          main_prompt: "Pick: {{pick::a,b,c}}",
          post_history_instructions: "",
        )

        plan1 = TavernKit.build(
          character: character,
          user: user,
          preset: preset,
          macro_vars: { pick_seed: 12_345 },
          message: "Hi"
        )

        plan2 = TavernKit.build(
          character: character,
          user: user,
          preset: preset,
          macro_vars: { pick_seed: 12_345 },
          message: "Hi"
        )

        result1 = plan1.messages.first.content
        result2 = plan2.messages.first.content

        assert_equal result1, result2
        assert_match(/\APick: (a|b|c)\z/, result1)
      end

      def test_last_generation_type_and_is_mobile_macros
        character = Character.create(name: "Alice", mes_example: "")
        user = User.new(name: "Bob")

        preset = Preset.new(
          main_prompt: "{{lastGenerationType}}|{{isMobile}}",
          post_history_instructions: "",
        )

        normal = TavernKit.build(character: character, user: user, preset: preset, message: "Hi")
        assert_equal "normal|false", normal.messages.first.content

        cont = TavernKit.build(character: character, user: user, preset: preset, generation_type: :continue, message: "Hi")
        assert_equal "continue|false", cont.messages.first.content

        overridden = TavernKit.build(character: character, user: user, preset: preset, macro_vars: { isMobile: true }, message: "Hi")
        assert_equal "normal|true", overridden.messages.first.content
      end

      def test_st_variable_macro_names_work_in_pipeline
        character = Character.create(name: "Alice", mes_example: "")
        user = User.new(name: "Bob")
        variables = ChatVariables.new

        preset = Preset.new(
          main_prompt: "{{setvar::x::1}}{{addvar::x::2}}{{getvar::x}}",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: user, preset: preset, macro_vars: { local_store: variables }, message: "Hi")
        assert_includes plan.messages.first.content, "3"
        assert_equal "3", variables["x"]
      end

      def test_global_variable_macros_work_in_pipeline
        character = Character.create(name: "Alice", mes_example: "")
        user = User.new(name: "Bob")
        globals = ChatVariables.new

        preset = Preset.new(
          main_prompt: "{{setglobalvar::g::hello}}{{getglobalvar::g}}",
          post_history_instructions: "",
        )

        plan = TavernKit.build(character: character, user: user, preset: preset, macro_vars: { global_store: globals }, message: "Hi")
        assert_includes plan.messages.first.content, "hello"
        assert_equal "hello", globals["g"]
      end

      def test_custom_macro_values_are_sanitized_like_st
        character = Character.create(name: "Alice", mes_example: "")
        user = User.new(name: "Bob")

        preset = Preset.new(
          main_prompt: "OBJ={{obj}}",
          post_history_instructions: "",
        )

        begin
          TavernKit.macros.register("obj") { |_ctx, _inv| { "a" => 1 } }
          plan = TavernKit.build(character: character, user: user, preset: preset, message: "Hi")
          assert_equal "OBJ={\"a\":1}", plan.messages.first.content
        ensure
          TavernKit.macros.unregister("obj")
        end
      end
    end
  end
end
