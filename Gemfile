# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in tavern_kit.gemspec
gemspec

# easy_talk 3.2.0 defines `property` twice (Ruby warns). Use upstream main until a fixed release.
gem "easy_talk", github: "sergiobayona/easy_talk"

gem "irb"
gem "rake", "~> 13.0"

gem "minitest", "~> 6"

gem "simplecov", require: false

gem "rubocop", "~> 1.21"
gem "rubocop-rails-omakase", require: false

eval_gemfile "playground/Gemfile.app"
