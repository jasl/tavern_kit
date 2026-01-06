# frozen_string_literal: true

module LLMSettings
  class FieldEnumerator
    def initialize(schema:)
      @schema = schema
    end

    # Enumerate leaf fields under participant for server-side rendering.
    # Includes both llm and preset settings.
    #
    # Output format is tailored for app/views/settings/fields partials.
    #
    # @param settings [Hash] Participant#settings (JSON column)
    # @return [Array<Hash>]
    def participant_llm_fields(settings:)
      participant = @schema.dig("properties", "participant")
      return [] unless participant.is_a?(Hash)

      fields = []

      # Enumerate llm settings
      llm = participant.dig("properties", "llm")
      if llm.is_a?(Hash)
        walk_fields(
          llm,
          path: ["llm"],
          group_label: nil,
          visible_when: nil,
          disabled: false,
          disabled_reason: nil,
          out: fields,
          setting_path_prefix: "settings"
        ) do |path, node|
          dig_setting(settings || {}, path).then do |value|
            value = node["default"] if value.nil? && node.key?("default")
            value
          end
        end
      end

      # Enumerate preset settings
      preset = participant.dig("properties", "preset")
      if preset.is_a?(Hash)
        walk_fields(
          preset,
          path: ["preset"],
          group_label: nil,
          visible_when: nil,
          disabled: false,
          disabled_reason: nil,
          out: fields,
          setting_path_prefix: "settings"
        ) do |path, node|
          dig_setting(settings || {}, path).then do |value|
            value = node["default"] if value.nil? && node.key?("default")
            value
          end
        end
      end

      fields
    end

    # Enumerate leaf fields under space schema for server-side rendering.
    #
    # The form posts schema-shaped patches (under the `settings` key), which are
    # later mapped to Space storage using `x-storage` metadata.
    #
    # @param space [Space]
    # @return [Array<Hash>]
    def space_fields(space:)
      space_schema = @schema.dig("properties", "space")
      return [] unless space_schema.is_a?(Hash)

      fields = []

      walk_fields(
        space_schema,
        path: [],
        group_label: nil,
        visible_when: nil,
        disabled: false,
        disabled_reason: nil,
        out: fields,
        setting_path_prefix: "settings"
      ) do |_path, node|
        value_from_storage(space, node).then do |value|
          value = node["default"] if value.nil? && node.key?("default")
          value
        end
      end

      fields
    end

    # Enumerate leaf fields under character schema for server-side rendering.
    #
    # @param character [Character]
    # @return [Array<Hash>]
    def character_fields(character:)
      character_schema = @schema.dig("properties", "character")
      return [] unless character_schema.is_a?(Hash)

      fields = []

      walk_fields(
        character_schema,
        path: [],
        group_label: nil,
        visible_when: nil,
        disabled: false,
        disabled_reason: nil,
        out: fields,
        setting_path_prefix: "data"
      ) do |path, node|
        dig_setting(character.data || {}, path).then do |value|
          value = node["default"] if value.nil? && node.key?("default")
          value
        end
      end

      fields
    end

    private

    def walk_fields(node, path:, group_label:, visible_when:, disabled:, disabled_reason:, out:, setting_path_prefix:, &value_for_leaf)
      return unless node.is_a?(Hash)

      ui = node["x-ui"] || {}

      group_label =
        if ui["group"].present?
          ui["group"]
        elsif ui["control"] == "group" && ui["label"].present?
          ui["label"]
        else
          group_label
        end

      visible_when = ui["visibleWhen"] || visible_when

      disabled_here = node["disabled"] == true || ui["disabled"] == true
      disabled = disabled || disabled_here

      disabled_reason = ui["disabledReason"] || disabled_reason

      properties = node["properties"]
      if properties.is_a?(Hash)
        properties.each do |key, child|
          walk_fields(
            child,
            path: path + [key],
            group_label: group_label,
            visible_when: visible_when,
            disabled: disabled,
            disabled_reason: disabled_reason,
            out: out,
            setting_path_prefix: setting_path_prefix,
            &value_for_leaf
          )
        end
        return
      end

      type = normalize_type(node["type"])
      return if type == "object"

      key = path.last
      setting_path = "#{setting_path_prefix}.#{path.join('.')}"
      value = value_for_leaf.call(path, node)

      leaf_ui = node["x-ui"] || {}
      control = leaf_ui["control"]

      # Determine tab: explicit "tab" takes precedence, fallback to "quick" for compatibility
      ui_tab = leaf_ui["tab"]
      ui_tab ||= "basic" if leaf_ui["quick"] == true

      out << {
        key: key,
        label: leaf_ui["label"] || key.to_s.humanize,
        type: type,
        control: control,
        enum: node["enum"],
        enum_labels: leaf_ui["enumLabels"],
        description: node["description"],
        default: node["default"],
        value: value,
        max_items: node["maxItems"],
        minimum: node["minimum"],
        maximum: node["maximum"],
        step: leaf_ui.dig("range", "step"),
        range: leaf_ui["range"],
        rows: leaf_ui["rows"],
        ui_tab: ui_tab,
        ui_order: leaf_ui["order"],
        ui_group: group_label,
        visible_when: visible_when,
        disabled: disabled,
        disabled_reason: disabled_reason,
        setting_path: setting_path,
      }
    end

    def normalize_type(type)
      return nil if type.nil?

      if type.is_a?(Array)
        type = type.reject { |t| t == "null" }.first
      end

      type
    end

    def dig_setting(settings, path)
      current = settings

      path.each do |segment|
        return nil unless current.is_a?(Hash)

        current = current[segment]
      end

      current
    end

    def value_from_storage(model, node)
      storage = node["x-storage"]
      return nil unless storage.is_a?(Hash)

      raw = case storage["kind"]
      when "column"
              model.public_send(storage.fetch("attr"))
      when "json"
              container = model.public_send(storage.fetch("attr")) || {}
              dig_json(container, storage.fetch("path"))
      end

      mapping = storage["mapping"]
      return raw unless mapping.is_a?(Hash)

      mapping.invert.fetch(raw, raw)
    end

    def dig_json(hash, path)
      current = hash

      path.each do |segment|
        return nil unless current.is_a?(Hash)

        current = current[segment]
      end

      current
    end
  end
end
