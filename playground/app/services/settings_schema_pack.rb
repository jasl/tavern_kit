# frozen_string_literal: true

require "digest"

# SettingsSchemaPack provides access to the bundled settings schema.
#
# This module generates JSON Schema from Ruby class definitions
# using EasyTalk-based schema classes.
#
module SettingsSchemaPack
  class << self
    def bundle
      @bundle ||= LLMSettings::Bundler.new.bundle
    end

    def bundle_json
      JSON.pretty_generate(bundle)
    end

    def digest
      @digest ||= Digest::SHA256.hexdigest(JSON.generate(bundle))
    end

    # Reload the schema (useful in development when iterating on schema classes).
    def reload!
      @bundle = nil
      @digest = nil
    end
  end
end
