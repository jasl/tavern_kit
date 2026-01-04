# frozen_string_literal: true

module SettingsSchemas
  class Loader
    LoadedDocument = Data.define(:relative_path, :absolute_path, :json)

    def initialize(root_dir: Rails.root.join("app/settings_schemas"))
      @root_dir = Pathname(root_dir)
      @memo = {}
    end

    # Load a JSON file by a pack-relative path.
    #
    # @param relative_path [String]
    # @return [Hash]
    def load_json(relative_path)
      load_document(relative_path).json
    end

    # Load a document by a pack-relative path.
    #
    # @param relative_path [String]
    # @return [LoadedDocument]
    def load_document(relative_path)
      abs_path = @root_dir.join(relative_path).cleanpath
      load_document_by_absolute_path(abs_path)
    end

    # Load a document by absolute path.
    #
    # @param abs_path [String, Pathname]
    # @return [LoadedDocument]
    def load_document_by_absolute_path(abs_path)
      abs_path = Pathname(abs_path).cleanpath
      key = abs_path.to_s

      parsed = (@memo[key] ||= JSON.parse(File.read(abs_path)))
      relative_path = abs_path.relative_path_from(@root_dir).to_s

      LoadedDocument.new(
        relative_path: relative_path,
        absolute_path: abs_path.to_s,
        json: deep_dup(parsed)
      )
    end

    private

    def deep_dup(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), out| out[k] = deep_dup(v) }
      when Array
        value.map { |v| deep_dup(v) }
      else
        value
      end
    end
  end
end
