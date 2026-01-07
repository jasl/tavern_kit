# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in tavern_kit.gemspec
gemspec

# easy_talk 3.2.0 defines `property` twice (Ruby warns). Use upstream main until a fixed release.
gem "easy_talk", github: "sergiobayona/easy_talk"

gem "irb"
gem "rake", "~> 13.0"

# Pin minitest to 5.x for Rails 8.1 compatibility
# (minitest 6.0 changed the Runnable#run method signature)
gem "minitest", "~> 5.25"

gem "simplecov", require: false

gem "rubocop", "~> 1.21"
gem "rubocop-rails-omakase", require: false

eval_gemfile "playground/Gemfile"
