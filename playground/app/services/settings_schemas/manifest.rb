# frozen_string_literal: true

module SettingsSchemas
  class Manifest
    DEFAULT_ROOT_DIR = Rails.root.join("app/settings_schemas")
    DEFAULT_MANIFEST_PATH = DEFAULT_ROOT_DIR.join("manifest.json")

    attr_reader :root_dir

    def initialize(root_dir: DEFAULT_ROOT_DIR, manifest_path: DEFAULT_MANIFEST_PATH)
      @root_dir = Pathname(root_dir)
      @manifest_path = Pathname(manifest_path)
    end

    def root_schema_path
      data.fetch("root")
    end

    def extensions_dir
      dir = data.dig("extensions", "dir")
      dir ? root_dir.join(dir) : root_dir.join("extensions")
    end

    def data
      @data ||= JSON.parse(File.read(@manifest_path))
    end
  end
end
