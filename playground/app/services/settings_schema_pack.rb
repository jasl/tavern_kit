# frozen_string_literal: true

require "digest"

module SettingsSchemaPack
  class << self
    def bundle
      @bundle ||= SettingsSchemas::Bundler.new.bundle
    end

    def bundle_json
      JSON.pretty_generate(bundle)
    end

    def digest
      @digest ||= Digest::SHA256.hexdigest(JSON.generate(bundle))
    end

    # Useful in development when iterating on schema files.
    def reload!
      @bundle = nil
      @digest = nil
    end
  end
end
