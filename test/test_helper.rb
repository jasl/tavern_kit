# frozen_string_literal: true

# SimpleCov must be started before any application code is loaded
require "simplecov"
SimpleCov.start do
  enable_coverage :branch

  add_filter "/test/"
  add_filter "/tmp/"
  add_filter "/playground/"

  add_group "Core", %w[lib/tavern_kit.rb lib/tavern_kit/version.rb lib/tavern_kit/errors.rb lib/tavern_kit/constants.rb]
  add_group "Character", %w[lib/tavern_kit/character.rb lib/tavern_kit/character_card.rb lib/tavern_kit/user.rb lib/tavern_kit/participant.rb]
  add_group "Chat", %w[lib/tavern_kit/chat_history lib/tavern_kit/chat_variables]
  add_group "Lore", "lib/tavern_kit/lore"
  add_group "Macro", %w[lib/tavern_kit/macro lib/tavern_kit/macro_context.rb lib/tavern_kit/macro_registry.rb]
  add_group "Prompt", "lib/tavern_kit/prompt"
  add_group "Preset", %w[lib/tavern_kit/preset lib/tavern_kit/preset.rb]
  add_group "PNG", "lib/tavern_kit/png"
  add_group "Utils", %w[lib/tavern_kit/utils.rb lib/tavern_kit/coerce.rb lib/tavern_kit/token_estimator.rb]
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "tavern_kit"

require "minitest/autorun"
