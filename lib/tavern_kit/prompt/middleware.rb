# frozen_string_literal: true

# Middleware loader for prompt pipeline
require_relative "middleware/base"
require_relative "middleware/hooks"
require_relative "middleware/lore"
require_relative "middleware/entries"
require_relative "middleware/pinned_groups"
require_relative "middleware/injection"
require_relative "middleware/compilation"
require_relative "middleware/macro_expansion"
require_relative "middleware/plan_assembly"
require_relative "middleware/trimming"

module TavernKit
  module Prompt
    # Namespace for pipeline middlewares.
    #
    # Middlewares are ordered processing units that transform a Context
    # object through the prompt building pipeline.
    #
    # @example Using middlewares in a pipeline
    #   pipeline = Pipeline.new do
    #     use Middleware::Hooks
    #     use Middleware::Lore
    #     use Middleware::Entries
    #     use Middleware::PinnedGroups
    #     use Middleware::Injection
    #     use Middleware::Compilation
    #     use Middleware::MacroExpansion
    #     use Middleware::PlanAssembly
    #     use Middleware::Trimming
    #   end
    #
    module Middleware
    end
  end
end
