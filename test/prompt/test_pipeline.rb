# frozen_string_literal: true

require_relative "../test_helper"

class TestPromptPipeline < Minitest::Test
  include TavernKit

  def setup
    @character = Character.create(
      name: "Alice",
      description: "A helpful assistant",
      personality: "Friendly and kind",
      scenario: "A casual conversation",
      first_mes: "Hello! How can I help you today?",
      mes_example: "<START>\n{{user}}: Hi\n{{char}}: Hello!"
    )

    @user = User.new(name: "Bob", persona: "A curious student")

    @preset = Preset.new(
      main_prompt: "You are {{char}}, speaking with {{user}}."
    )
  end

  # ============================================
  # Pipeline Core Tests
  # ============================================

  def test_pipeline_default_has_all_middlewares
    pipeline = Prompt::Pipeline.default

    assert pipeline.has?(:hooks)
    assert pipeline.has?(:lore)
    assert pipeline.has?(:entries)
    assert pipeline.has?(:pinned_groups)
    assert pipeline.has?(:injection)
    assert pipeline.has?(:compilation)
    assert pipeline.has?(:macro_expansion)
    assert pipeline.has?(:plan_assembly)
    assert pipeline.has?(:trimming)

    assert_equal 9, pipeline.size
  end

  def test_pipeline_middleware_ordering
    pipeline = Prompt::Pipeline.default

    expected_order = %i[
      hooks
      lore
      entries
      pinned_groups
      injection
      compilation
      macro_expansion
      plan_assembly
      trimming
    ]

    assert_equal expected_order, pipeline.names
  end

  def test_pipeline_replace_middleware
    pipeline = Prompt::Pipeline.default.dup

    custom_class = Class.new(Prompt::Middleware::Base)
    pipeline.replace(:lore, custom_class)

    assert_equal custom_class, pipeline[:lore].middleware
  end

  def test_pipeline_insert_before
    pipeline = Prompt::Pipeline.default.dup

    custom_class = Class.new(Prompt::Middleware::Base)
    pipeline.insert_before(:lore, custom_class, name: :custom)

    assert pipeline.has?(:custom)
    assert_equal [:hooks, :custom, :lore], pipeline.names.first(3)
  end

  def test_pipeline_insert_after
    pipeline = Prompt::Pipeline.default.dup

    custom_class = Class.new(Prompt::Middleware::Base)
    pipeline.insert_after(:hooks, custom_class, name: :custom)

    assert pipeline.has?(:custom)
    assert_equal [:hooks, :custom, :lore], pipeline.names.first(3)
  end

  def test_pipeline_remove_middleware
    pipeline = Prompt::Pipeline.default.dup
    pipeline.remove(:trimming)

    refute pipeline.has?(:trimming)
    assert_equal 8, pipeline.size
  end

  def test_pipeline_configure_middleware
    pipeline = Prompt::Pipeline.default.dup
    pipeline.configure(:macro_expansion, custom_option: true)

    entry = pipeline[:macro_expansion]
    assert_equal true, entry.options[:custom_option]
  end

  # ============================================
  # Context Tests
  # ============================================

  def test_context_initialization
    ctx = Prompt::Context.new(
      character: @character,
      user: @user,
      user_message: "Hello!"
    )

    assert_equal @character, ctx.character
    assert_equal @user, ctx.user
    assert_equal "Hello!", ctx.user_message
    assert_equal :normal, ctx.generation_type
    assert_equal [], ctx.warnings
  end

  def test_context_metadata
    ctx = Prompt::Context.new

    ctx[:custom_key] = "custom_value"
    assert_equal "custom_value", ctx[:custom_key]
    assert ctx.key?(:custom_key)
  end

  def test_context_warnings
    ctx = Prompt::Context.new(warning_handler: nil)

    ctx.warn("Test warning")
    assert_includes ctx.warnings, "Test warning"
  end

  def test_context_validate_raises_without_character
    ctx = Prompt::Context.new(user: @user)

    assert_raises(ArgumentError) { ctx.validate! }
  end

  def test_context_validate_raises_without_user
    ctx = Prompt::Context.new(character: @character)

    assert_raises(ArgumentError) { ctx.validate! }
  end

  def test_context_dup_creates_independent_copy
    ctx = Prompt::Context.new(
      character: @character,
      user: @user,
      warning_handler: nil # Suppress stderr output during test
    )
    ctx.warn("Original warning")

    copy = ctx.dup
    copy.warn("Copy warning")

    assert_equal 1, ctx.warnings.size
    assert_equal 2, copy.warnings.size
  end

  # ============================================
  # DSL Tests
  # ============================================

  def test_dsl_build_with_block
    char = Character.create(name: "TestChar", description: "Test description")
    usr = User.new(name: "TestUser")

    plan = Prompt::DSL.build do
      character char
      user usr
      message "Hello from DSL!"
    end

    assert_instance_of Prompt::Plan, plan
  end

  def test_dsl_fluent_api
    dsl = Prompt::DSL.new
      .character(@character)
      .user(@user)
      .preset(@preset)
      .message("Hello!")

    plan = dsl.build

    assert_instance_of Prompt::Plan, plan
  end

  def test_dsl_with_custom_pipeline
    custom_pipeline = Prompt::Pipeline.default.dup
    custom_pipeline.remove(:trimming)

    char = Character.create(name: "TestChar", description: "Test description")
    usr = User.new(name: "TestUser")

    plan = Prompt::DSL.build(pipeline: custom_pipeline) do
      character char
      user usr
      message "Hello!"
    end

    assert_instance_of Prompt::Plan, plan
  end

  def test_dsl_replace_middleware
    plan = TavernKit::Prompt::DSL.new
      .character(@character)
      .user(@user)
      .message("Hello!")

    # Should not raise
    plan.build
  end

  # ============================================
  # Integration Tests
  # ============================================

  def test_top_level_build_with_block
    char = Character.create(name: "IntegrationChar", description: "Integration test character")
    usr = User.new(name: "IntegrationUser")

    plan = TavernKit.build do
      character char
      user usr
      message "Integration test message"
    end

    assert_instance_of Prompt::Plan, plan
  end

  def test_top_level_build_with_kwargs
    plan = TavernKit.build(
      character: @character,
      user: @user,
      message: "Hello from kwargs!"
    )

    assert_instance_of Prompt::Plan, plan
  end

  def test_prompt_build_module_method
    char = Character.create(name: "ModuleChar", description: "Module test character")
    usr = User.new(name: "ModuleUser")

    plan = Prompt.build do
      character char
      user usr
      message "Module test message"
    end

    assert_instance_of Prompt::Plan, plan
  end

  def test_to_messages_with_dsl
    char = Character.create(name: "MessagesChar", description: "Messages test character")
    usr = User.new(name: "MessagesUser")

    messages = Prompt::DSL.to_messages(dialect: :openai) do
      character char
      user usr
      message "Messages test"
    end

    assert_instance_of Array, messages
  end
end
