# frozen_string_literal: true

module ConversationSettings
  # Convert a JavaScript regex literal (e.g. `/^\\d+$/`) into a Ruby regex pattern
  # string suitable for Rails validations and EasyTalk schemas.
  #
  # NOTE: JSON Schema `pattern` does not support regex flags. If flags are present
  # (e.g. `/foo/i`), we raise to avoid silently dropping behavior.
  #
  # @param literal [String] JS regex literal, like `/^foo$/`
  # @return [String] Ruby regex source (often using \A and \z anchors)
  def self.js_regex_literal_to_ruby_pattern(literal)
    re = ::JsRegexToRuby.try_convert(literal.to_s, literal_only: true)
    raise ArgumentError, "Invalid JS regex literal: #{literal.inspect}" unless re

    if re.options != 0
      raise ArgumentError, "JS regex flags are not supported in JSON Schema patterns: #{literal.inspect}"
    end

    re.source
  end

  # Base module for EasyTalk-based settings schema definitions.
  #
  # This module extends EasyTalk::Model with support for custom JSON Schema
  # extension keywords like `x-ui` (for frontend form rendering) and `x-storage`
  # (for backend data persistence mapping).
  #
  # == Usage
  #
  #   class GenerationSettings
  #     include ConversationSettings::Base
  #
  #     schema_id "schema://settings/defs/generation"
  #
  #     define_schema do
  #       title "Generation Settings"
  #       property :temperature, Float, default: 1.0, minimum: 0, maximum: 2
  #     end
  #
  #     define_ui_extensions(
  #       temperature: { label: "Temperature", control: :slider, quick: true }
  #     )
  #
  #     define_storage_extensions(
  #       temperature: { model: "Space", attr: "settings", kind: "json", path: ["temperature"] }
  #     )
  #   end
  #
  module Base
    extend ActiveSupport::Concern

    included do
      include EasyTalk::Model

      class_attribute :schema_id_value, default: nil
      class_attribute :schema_tab_value, default: nil
      class_attribute :ui_extensions, default: {}
      class_attribute :storage_extensions, default: {}
      class_attribute :nested_schemas, default: {}
    end

    class_methods do
      # Set the JSON Schema $id for this schema.
      def schema_id(value)
        self.schema_id_value = value
      end

      # Set the UI tab for this schema (used at top-level schemas).
      def schema_tab(name:, icon: nil, order: nil)
        self.schema_tab_value = { tab: name, icon: icon, order: order }.compact
      end

      # Define UI rendering hints for properties.
      #
      # @param extensions [Hash{Symbol => Hash}] Property name to UI options mapping
      def define_ui_extensions(extensions)
        self.ui_extensions = ui_extensions.merge(extensions)
      end

      # Define storage mapping hints for properties.
      #
      # @param extensions [Hash{Symbol => Hash}] Property name to storage options mapping
      def define_storage_extensions(extensions)
        self.storage_extensions = storage_extensions.merge(extensions)
      end

      # Define nested schema references.
      #
      # @param refs [Hash{Symbol => Class, String, Proc}] Property name to schema class mapping
      #   Values can be:
      #   - Class: Direct class reference
      #   - String: Class name for lazy loading (e.g., "ConversationSettings::SpaceSettings")
      #   - Proc: Lambda that returns the class (for circular references)
      def define_nested_schemas(refs)
        self.nested_schemas = nested_schemas.merge(refs)
      end

      # Resolve a nested schema reference to its class.
      def resolve_nested_schema(ref)
        case ref
        when Class
          ref
        when String
          ref.constantize
        when Proc
          ref.call
        else
          raise ArgumentError, "Invalid nested schema reference: #{ref.inspect}"
        end
      end

      # Returns JSON Schema with all extensions merged in.
      #
      # @return [Hash] Complete JSON Schema with extensions
      def json_schema_extended
        schema = json_schema.deep_dup
        convert_ruby_regex_anchors_to_ecma262!(schema)

        # Add $schema and $id if present
        if schema_id_value
          schema = { "$schema" => "https://json-schema.org/draft/2020-12/schema", "$id" => schema_id_value }.merge(schema)
        end

        # Add top-level x-ui (tab info) if present
        if schema_tab_value
          schema["x-ui"] = deep_stringify(schema_tab_value)
        end

        # Ensure properties hash exists
        schema["properties"] ||= {}

        # Expand nested schemas first (they need to be added to properties)
        nested_schemas.each do |prop_name, schema_ref|
          prop_key = prop_name.to_s

          schema_class = resolve_nested_schema(schema_ref)
          nested = schema_class.json_schema_extended

          # Merge with existing property (if any) or create new
          if schema["properties"][prop_key]
            existing_ui = schema["properties"][prop_key]["x-ui"]
            schema["properties"][prop_key] = nested
            schema["properties"][prop_key]["x-ui"] = existing_ui if existing_ui
          else
            schema["properties"][prop_key] = nested
          end
        end

        # Merge x-ui extensions into properties
        ui_extensions.each do |prop_name, ui_opts|
          prop_key = prop_name.to_s
          next unless schema.dig("properties", prop_key)

          schema["properties"][prop_key]["x-ui"] = deep_stringify(ui_opts)
        end

        # Merge x-storage extensions into properties
        storage_extensions.each do |prop_name, storage_opts|
          prop_key = prop_name.to_s
          next unless schema.dig("properties", prop_key)

          schema["properties"][prop_key]["x-storage"] = deep_stringify(storage_opts)
        end

        schema
      end

      # Export schema as JSON string (with extensions)
      #
      # @param pretty [Boolean] Whether to pretty-print the JSON
      # @return [String] JSON Schema string
      def to_json_schema(pretty: true)
        if pretty
          JSON.pretty_generate(json_schema_extended)
        else
          json_schema_extended.to_json
        end
      end

      private

      # JSON Schema `pattern` uses ECMA-262 regular expressions. Ruby-specific anchors
      # like \A and \z would be treated as literal "A"/"z" escapes in JavaScript and
      # break validation. We keep Ruby-safe anchors in the schema DSL (to satisfy
      # ActiveModel validations) and translate them on export.
      def convert_ruby_regex_anchors_to_ecma262!(node)
        case node
        when Hash
          if (pattern = node["pattern"]).is_a?(String)
            node["pattern"] =
              pattern
                .sub(/\A\\A/, "^")
                .sub(/\\z\z/, "$")
                .sub(/\\Z\z/, "$")
          end

          node.each_value { |v| convert_ruby_regex_anchors_to_ecma262!(v) }
        when Array
          node.each { |v| convert_ruby_regex_anchors_to_ecma262!(v) }
        end

        node
      end

      def deep_stringify(value)
        case value
        when Hash
          value.transform_keys(&:to_s).transform_values { |v| deep_stringify(v) }
        when Array
          value.map { |v| deep_stringify(v) }
        when Symbol
          value.to_s
        else
          value
        end
      end
    end
  end
end
