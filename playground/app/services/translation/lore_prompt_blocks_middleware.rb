# frozen_string_literal: true

module Translation
  class LorePromptBlocksMiddleware < ::TavernKit::Prompt::Middleware::Base
    def initialize(app, translator:, **options)
      super(app, **options)
      @translator = translator
    end

    private

    attr_reader :translator

    def before(ctx)
      return unless ctx.plan
      return unless translator

      ctx.plan = translator.translate_plan_lore(ctx.plan)
    end
  end
end
