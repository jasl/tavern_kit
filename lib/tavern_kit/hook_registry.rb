# frozen_string_literal: true

module TavernKit
  # A per-builder registry for build-time hooks.
  #
  # Hooks run in registration order.
  #
  # This is inspired by SillyTavern's extension interception approach:
  # callers can intercept prompt construction before inputs are processed and
  # after the prompt plan is assembled.
  class HookRegistry
    def initialize
      @before_build = []
      @after_build = []
    end

    # Register a hook to run before the prompt plan is built.
    #
    # The hook receives a {HookContext} and may mutate:
    # - character, user, history, user_message
    #
    # @yieldparam ctx [HookContext]
    # @return [self]
    def before_build(&block)
      raise ArgumentError, "before_build requires a block" unless block

      @before_build << block
      self
    end

    # Register a hook to run after the prompt plan is built (but before trimming).
    #
    # The hook receives a {HookContext} and may mutate/replace:
    # - plan (and plan.blocks)
    #
    # @yieldparam ctx [HookContext]
    # @return [self]
    def after_build(&block)
      raise ArgumentError, "after_build requires a block" unless block

      @after_build << block
      self
    end

    # @return [Boolean] true if no hooks are registered
    def empty?
      @before_build.empty? && @after_build.empty?
    end

    # Run all before_build hooks in order.
    # @param context [HookContext]
    def run_before_build(context)
      @before_build.each { |hook| hook.call(context) }
    end

    # Run all after_build hooks in order.
    # @param context [HookContext]
    def run_after_build(context)
      @after_build.each { |hook| hook.call(context) }
    end

    # Deep-ish copy suitable for independent use.
    def dup
      copy = self.class.new
      copy.instance_variable_set(:@before_build, @before_build.dup)
      copy.instance_variable_set(:@after_build, @after_build.dup)
      copy
    end
  end

  # Context object passed to build-time hooks.
  #
  # Hooks receive a snapshot of the build state and may mutate selected fields.
  class HookContext
    attr_accessor :character, :user, :history, :user_message, :plan
    attr_reader :preset, :generation_type, :injection_registry, :macro_vars, :group

    def initialize(
      character:,
      user:,
      history:,
      user_message:,
      preset:,
      generation_type:,
      injection_registry:,
      macro_vars:,
      group:
    )
      @character = character
      @user = user
      @history = history
      @user_message = user_message
      @preset = preset
      @generation_type = generation_type
      @injection_registry = injection_registry
      @macro_vars = macro_vars
      @group = group
      @plan = nil
    end
  end
end
