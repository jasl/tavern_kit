# frozen_string_literal: true

module ConversationSettings
  class StorageApplier
    class Error < StandardError; end

    def initialize(schema:)
      @schema = schema
    end

    # Apply a schema-shaped patch to a model instance, using `x-storage`.
    #
    # This is intentionally not a full JSON Schema validator. It only maps
    # leaf values to either:
    # - model columns (`kind: "column"`)
    # - model JSON attrs (`kind: "json"`, with a JSON path array)
    #
    # @param model [ApplicationRecord]
    # @param patch [Hash] schema-shaped object patch
    # @return [Hash] ActiveRecord update hash (e.g. { settings: {...}, card_handling_mode: "swap" })
    def apply(model:, patch:)
      raise Error, "patch must be an object" unless patch.is_a?(Hash)

      updates = {}
      json_updates = {}

      walk_patch(@schema, patch, path: []) do |schema_node, value|
        storage = schema_node["x-storage"]
        next unless storage.is_a?(Hash)

        mapped_value = map_value(value, storage["mapping"])

        case storage["kind"]
        when "column"
          attr = storage.fetch("attr")
          updates[attr.to_sym] = mapped_value
        when "json"
          attr = storage.fetch("attr")
          json_updates[attr] ||= (model.public_send(attr) || {}).deep_dup
          set_json_path(json_updates[attr], storage.fetch("path"), mapped_value)
        end
      end

      json_updates.each do |attr, value|
        updates[attr.to_sym] = value
      end

      updates
    end

    private

    def walk_patch(schema_node, patch_node, path:, &block)
      return unless patch_node.is_a?(Hash)

      properties = schema_node["properties"]
      raise Error, "schema node at #{format_path(path)} must be an object" unless properties.is_a?(Hash)

      patch_node.each do |key, value|
        child_schema = properties[key]
        raise Error, "Unknown setting: #{format_path(path + [key])}" unless child_schema.is_a?(Hash)

        if value.is_a?(Hash) && child_schema["properties"].is_a?(Hash)
          walk_patch(child_schema, value, path: path + [key], &block)
        else
          yield(child_schema, value)
        end
      end
    end

    def set_json_path(hash, path, value)
      raise Error, "x-storage.path must be a non-empty array" unless path.is_a?(Array) && path.any?

      current = hash
      path[0..-2].each do |segment|
        current[segment] = {} unless current[segment].is_a?(Hash)
        current = current[segment]
      end

      current[path[-1]] = value
    end

    def map_value(value, mapping)
      return value unless mapping.is_a?(Hash)

      return value unless mapping.key?(value)

      mapping[value]
    end

    def format_path(path)
      return "/" if path.empty?

      "/" + path.join("/")
    end
  end
end
