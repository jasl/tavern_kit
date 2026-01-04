# frozen_string_literal: true

module LLMSettings
  # Bundler generates the complete JSON Schema from Ruby class definitions.
  #
  # This replaces the old file-based bundler that resolved $ref across JSON files.
  #
  class Bundler
    def initialize(root_schema: RootSchema)
      @root_schema = root_schema
    end

    # Generate the bundled JSON Schema.
    #
    # @return [Hash] Complete JSON Schema with all extensions
    def bundle
      @root_schema.json_schema_extended
    end

    # Generate the bundled JSON Schema as a pretty-printed string.
    #
    # @return [String] JSON Schema string
    def bundle_json
      JSON.pretty_generate(bundle)
    end
  end
end
