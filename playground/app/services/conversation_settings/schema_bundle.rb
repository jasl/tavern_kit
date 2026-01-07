# frozen_string_literal: true

require "digest"

# ConversationSettings::SchemaBundle provides access to the bundled settings schema.
#
# This module generates JSON Schema from Ruby class definitions
# (EasyTalk-based schema classes) and caches a digest for HTTP caching (ETag).
#
module ConversationSettings
  module SchemaBundle
    class << self
      def schema
        @schema ||= ConversationSettings::Bundler.new.bundle
      end

      def schema_json
        JSON.pretty_generate(schema)
      end

      def etag
        @etag ||= Digest::SHA256.hexdigest(JSON.generate(schema))
      end

      # Reload the schema (useful in development when iterating on schema classes).
      def reload!
        @schema = nil
        @etag = nil
      end
    end
  end
end
