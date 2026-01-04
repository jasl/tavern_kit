# frozen_string_literal: true

require "cgi"

module SettingsSchemas
  class RefResolver
    ResolvedRef = Data.define(:document, :fragment)

    def initialize(loader:)
      @loader = loader
    end

    # Resolve a $ref string starting from a document context.
    #
    # Supports:
    # - "defs/llm.schema.json"
    # - "defs/llm.schema.json#/$defs/SamplerSettings"
    # - "#/$defs/xxx"
    #
    # @param ref [String]
    # @param from_document [Loader::LoadedDocument]
    # @return [ResolvedRef]
    def resolve(ref, from_document:)
      document, pointer =
        if ref.start_with?("#")
          [from_document, ref]
        else
          path_part, fragment = ref.split("#", 2)
          abs = Pathname(from_document.absolute_path).dirname.join(path_part).cleanpath
          target = @loader.load_document_by_absolute_path(abs)
          [target, fragment ? "##{fragment}" : "#"]
        end

      fragment =
        if pointer == "#" || pointer == ""
          document.json
        else
          resolve_pointer(document.json, pointer)
        end

      ResolvedRef.new(document: document, fragment: fragment)
    end

    private

    def resolve_pointer(doc_json, pointer)
      pointer = pointer.to_s
      return doc_json if pointer == "#" || pointer == ""

      unless pointer.start_with?("#/")
        raise ArgumentError, "Unsupported JSON Pointer format: #{pointer.inspect}"
      end

      segments = pointer.delete_prefix("#/").split("/").map { |s| unescape_pointer_segment(s) }

      segments.reduce(doc_json) do |current, segment|
        if current.is_a?(Hash)
          current.fetch(segment)
        elsif current.is_a?(Array)
          current.fetch(Integer(segment))
        else
          raise KeyError, "Cannot resolve pointer #{pointer.inspect} at segment #{segment.inspect}"
        end
      end
    end

    def unescape_pointer_segment(segment)
      segment = CGI.unescape(segment)
      segment.gsub("~1", "/").gsub("~0", "~")
    end
  end
end
