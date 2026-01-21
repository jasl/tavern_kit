# frozen_string_literal: true

module CharacterExport
  # Exports a Character to PNG format with embedded metadata.
  #
  # Embeds character card data as tEXt chunks in the PNG file.
  # By default, embeds both CCv2 (chara) and CCv3 (ccv3) for compatibility.
  #
  # @example Export with both formats
  #   exporter = PngExporter.new(character)
  #   png_data = exporter.execute
  #
  # @example Export V3 only
  #   exporter = PngExporter.new(character, format: :v3_only)
  #   png_data = exporter.execute
  #
  # @example Export to file
  #   exporter = PngExporter.new(character)
  #   exporter.export_to_file("/path/to/output.png")
  #
  class PngExporter < Base
    PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b
    IEND_TYPE = "IEND".b
    TEXT_TYPE = "tEXt".b

    V2_KEYWORD = "chara"
    V3_KEYWORD = "ccv3"

    # Export the character as PNG binary data.
    #
    # @return [String] PNG binary content with embedded character data
    # @raise [ExportError] if portrait is not attached or not a valid PNG
    def execute
      validate_portrait!

      portrait_bytes = portrait_content
      validate_png!(portrait_bytes)

      chunks_data = parse_png_chunks(portrait_bytes)
      filtered_chunks = remove_character_chunks(chunks_data[:chunks])
      new_chunks = build_character_chunks

      reconstruct_png(filtered_chunks, new_chunks)
    end

    # Export directly to a file.
    #
    # @param path [String] output file path
    # @return [Integer] bytes written
    def export_to_file(path)
      File.binwrite(path, execute)
    end

    # Export as a downloadable IO object.
    #
    # @return [StringIO] PNG content as StringIO
    def to_io
      StringIO.new(execute)
    end

    # Suggested filename for download.
    #
    # @return [String] filename with .png extension
    def suggested_filename
      sanitized_name = character.name.gsub(/[^a-zA-Z0-9_\-]/, "_").squeeze("_")
      "#{sanitized_name}.png"
    end

    # MIME type for the export.
    #
    # @return [String]
    def content_type
      "image/png"
    end

    private

    # Get the export format.
    #
    # @return [Symbol] :both, :v2_only, or :v3_only
    def export_format
      options.fetch(:format, :both)
    end

    # Validate that portrait is attached.
    #
    # @raise [ExportError] if portrait is not attached
    def validate_portrait!
      return if character.portrait.attached?

      raise ExportError, "Character must have a portrait attached to export as PNG"
    end

    # Validate that the content is a valid PNG.
    #
    # @param bytes [String] binary content
    # @raise [ExportError] if not a valid PNG
    def validate_png!(bytes)
      return if bytes&.start_with?(PNG_SIGNATURE)

      raise ExportError, "Avatar is not a valid PNG file"
    end

    # Parse PNG into chunks for manipulation.
    #
    # @param bytes [String] raw PNG bytes
    # @return [Hash] { signature:, chunks: [{type:, data:, raw:}, ...] }
    def parse_png_chunks(bytes)
      signature = bytes[0, 8]
      chunks = []
      pos = 8

      while pos < bytes.bytesize
        length = bytes[pos, 4].unpack1("N")
        pos += 4

        type = bytes[pos, 4]
        pos += 4

        data = bytes[pos, length]
        pos += length

        crc = bytes[pos, 4]
        pos += 4

        raw = [length].pack("N") + type + data + crc
        chunks << { type: type, data: data, raw: raw }

        break if type == IEND_TYPE
      end

      { signature: signature, chunks: chunks }
    end

    # Remove existing character-related chunks (chara, ccv3).
    #
    # @param chunks [Array<Hash>] parsed chunks
    # @return [Array<Hash>] filtered chunks
    def remove_character_chunks(chunks)
      chunks.reject do |chunk|
        next false unless chunk[:type] == TEXT_TYPE

        keyword = extract_text_keyword(chunk[:data])
        [V2_KEYWORD, V3_KEYWORD].include?(keyword&.downcase)
      end
    end

    # Extract keyword from tEXt chunk data.
    #
    # @param data [String] chunk data
    # @return [String, nil] keyword
    def extract_text_keyword(data)
      nul_pos = data.index("\x00")
      return nil if nul_pos.nil?

      data[0, nul_pos]
    end

    # Build character data chunks based on format.
    #
    # @return [Array<String>] array of raw chunk bytes
    def build_character_chunks
      chunks = []

      if export_format == :v2_only || export_format == :both
        v2_hash = build_v2_hash
        chunks << build_text_chunk(V2_KEYWORD, v2_hash)
      end

      if export_format == :v3_only || export_format == :both
        v3_hash = build_v3_hash
        chunks << build_text_chunk(V3_KEYWORD, v3_hash)
      end

      chunks
    end

    # Build a tEXt chunk with the given keyword and JSON payload.
    #
    # @param keyword [String] chunk keyword
    # @param json_hash [Hash] data to encode
    # @return [String] raw chunk bytes
    def build_text_chunk(keyword, json_hash)
      json_str = JSON.generate(json_hash)
      base64_data = Base64.strict_encode64(json_str)

      chunk_data = "#{keyword}\x00#{base64_data}"
      build_chunk(TEXT_TYPE, chunk_data)
    end

    # Build a raw PNG chunk.
    #
    # @param type [String] 4-byte chunk type
    # @param data [String] chunk data bytes
    # @return [String] raw chunk bytes
    def build_chunk(type, data)
      length_bytes = [data.bytesize].pack("N")
      crc_input = type + data
      crc = Zlib.crc32(crc_input)
      crc_bytes = [crc].pack("N")

      length_bytes + type + data + crc_bytes
    end

    # Reconstruct PNG bytes with new chunks inserted before IEND.
    #
    # @param chunks [Array<Hash>] existing chunks
    # @param new_chunks [Array<String>] new raw chunk bytes
    # @return [String] complete PNG bytes
    def reconstruct_png(chunks, new_chunks)
      output = PNG_SIGNATURE.dup

      chunks.each do |chunk|
        if chunk[:type] == IEND_TYPE
          new_chunks.each { |nc| output << nc }
        end

        output << chunk[:raw]
      end

      output
    end
  end

  # Export error for PNG export failures.
  class ExportError < StandardError; end
end
