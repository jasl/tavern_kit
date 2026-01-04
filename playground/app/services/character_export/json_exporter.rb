# frozen_string_literal: true

module CharacterExport
  # Exports a Character to JSON format.
  #
  # @example Export to JSON string
  #   exporter = JsonExporter.new(character, version: 3)
  #   json_string = exporter.call
  #
  # @example Export to file
  #   exporter = JsonExporter.new(character, version: 3)
  #   exporter.export_to_file("/path/to/output.json")
  #
  class JsonExporter < Base
    # Export the character as a JSON string.
    #
    # @return [String] JSON-encoded character card
    def call
      JSON.pretty_generate(export_card_hash)
    end

    # Export directly to a file.
    #
    # @param path [String] output file path
    # @return [Integer] bytes written
    def export_to_file(path)
      File.write(path, call)
    end

    # Export as a downloadable IO object.
    #
    # @return [StringIO] JSON content as StringIO
    def to_io
      StringIO.new(call)
    end

    # Suggested filename for download.
    #
    # @return [String] filename with .json extension
    def suggested_filename
      sanitized_name = character.name.gsub(/[^a-zA-Z0-9_\-]/, "_").squeeze("_")
      "#{sanitized_name}.json"
    end

    # MIME type for the export.
    #
    # @return [String]
    def content_type
      "application/json"
    end
  end
end
