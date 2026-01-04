# frozen_string_literal: true

module CharacterExport
  # Exports a Character to CharX format (ZIP archive).
  #
  # CharX files contain:
  # - card.json: CCv3 character card data
  # - assets/icon/image/main.png (or .jpg/.webp): Main avatar image (if attached)
  # - assets/<kind>/image/<name>.<ext>: Additional assets from character_assets
  #
  # @example Export to CharX
  #   exporter = CharxExporter.new(character)
  #   charx_data = exporter.call
  #
  # @example Export to file
  #   exporter = CharxExporter.new(character)
  #   exporter.export_to_file("/path/to/output.charx")
  #
  class CharxExporter < Base
    # Export the character as CharX (ZIP) binary data.
    #
    # @return [String] ZIP binary content
    def call
      build_charx_archive
    end

    # Export directly to a file.
    #
    # @param path [String] output file path
    # @return [Integer] bytes written
    def export_to_file(path)
      File.binwrite(path, call)
    end

    # Export as a downloadable IO object.
    #
    # @return [StringIO] CharX content as StringIO
    def to_io
      StringIO.new(call)
    end

    # Suggested filename for download.
    #
    # @return [String] filename with .charx extension
    def suggested_filename
      sanitized_name = character.name.gsub(/[^a-zA-Z0-9_\-]/, "_").squeeze("_")
      "#{sanitized_name}.charx"
    end

    # MIME type for the export.
    #
    # @return [String]
    def content_type
      "application/zip"
    end

    private

    # Build the CharX ZIP archive in memory.
    #
    # @return [String] ZIP binary content
    def build_charx_archive
      buffer = StringIO.new
      buffer.set_encoding("ASCII-8BIT")

      Zip::OutputStream.write_buffer(buffer) do |zos|
        # Write card.json (always CCv3 for CharX)
        write_card_json(zos)

        # Write main portrait if attached
        write_main_portrait(zos)

        # Write additional character assets
        write_character_assets(zos)
      end

      buffer.string
    end

    # Write card.json to the ZIP.
    #
    # @param zos [Zip::OutputStream]
    def write_card_json(zos)
      card_hash = build_charx_card_hash
      json_content = JSON.pretty_generate(card_hash)

      zos.put_next_entry("card.json")
      zos.write(json_content)
    end

    # Build the card hash with proper asset URIs for CharX.
    #
    # Uses embeded:// URI scheme as per CCv3 spec.
    # Note: "embeded" (not "embedded") is the correct spelling per spec.
    #
    # @return [Hash]
    def build_charx_card_hash
      # Always use V3 for CharX
      data_hash = character.data.dup

      # Build assets array with embeded:// URIs (spec uses "embeded" not "embedded")
      assets = []

      # Add main portrait as icon
      if character.portrait.attached?
        ext = portrait_extension
        path = zip_asset_path(kind: "icon", filename: "main.#{ext}")
        assets << {
          "type" => "icon",
          "uri" => "embeded://#{path}",
          "name" => "main",
          "ext" => ext,
        }
      end

      # Add character assets
      character.character_assets.each do |asset|
        # Build filename, avoiding double extensions
        base_name = strip_extension(asset.name, asset.ext)
        filename = "#{base_name}.#{asset.ext}"
        path = zip_asset_path(kind: asset.kind, filename: filename)
        assets << {
          "type" => asset.kind,
          "uri" => "embeded://#{path}",
          "name" => base_name,
          "ext" => asset.ext,
        }
      end

      data_hash["assets"] = assets if assets.any?
      data_hash["modification_date"] = Time.current.to_i

      {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => data_hash,
      }
    end

    # Write main portrait to the ZIP.
    #
    # @param zos [Zip::OutputStream]
    def write_main_portrait(zos)
      return unless character.portrait.attached?

      content = portrait_content
      ext = portrait_extension
      filename = zip_asset_path(kind: "icon", filename: "main.#{ext}")

      zos.put_next_entry(filename)
      zos.write(content)
    end

    # Write character assets to the ZIP.
    #
    # @param zos [Zip::OutputStream]
    def write_character_assets(zos)
      character.character_assets.each do |asset|
        # Build filename, avoiding double extensions
        base_name = strip_extension(asset.name, asset.ext)
        filename = "#{base_name}.#{asset.ext}"
        content = asset.blob.download

        zos.put_next_entry(zip_asset_path(kind: asset.kind, filename: filename))
        zos.write(content)
      end
    end

    # Build a CharX asset path within the ZIP.
    #
    # @param kind [String] asset kind (icon, emotion, etc.)
    # @param filename [String] asset filename including extension
    # @return [String] path like "assets/emotion/image/happy.png"
    def zip_asset_path(kind:, filename:)
      "assets/#{kind}/image/#{filename}"
    end

    # Strip extension from name if it matches the ext.
    #
    # @param name [String] asset name (may include extension)
    # @param ext [String] expected extension
    # @return [String] name without extension
    def strip_extension(name, ext)
      suffix = ".#{ext}"
      if name.downcase.end_with?(suffix.downcase)
        name[0...(name.length - suffix.length)]
      else
        name
      end
    end
  end
end
