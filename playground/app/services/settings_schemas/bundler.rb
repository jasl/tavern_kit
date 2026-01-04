# frozen_string_literal: true

require "set"

module SettingsSchemas
  class Bundler
    class CircularReferenceError < StandardError; end

    def initialize(
      manifest: Manifest.new,
      loader: Loader.new,
      ref_resolver: nil,
      extensions: nil
    )
      @manifest = manifest
      @loader = loader
      @ref_resolver = ref_resolver || RefResolver.new(loader: loader)
      @extensions = extensions || Extensions.new(_extensions_dir: manifest.extensions_dir)
    end

    def bundle
      root_doc = @loader.load_document(@manifest.root_schema_path)
      bundled = dereference(root_doc.json, current_document: root_doc, ref_stack: Set.new, ref_chain: [])
      @extensions.apply_extensions(bundled)
    end

    private

    def dereference(node, current_document:, ref_stack:, ref_chain:)
      case node
      when Hash
        if node.key?("$ref")
          return dereference_ref(node, current_document: current_document, ref_stack: ref_stack, ref_chain: ref_chain)
        end

        if node["allOf"].is_a?(Array)
          return dereference_all_of(node, current_document: current_document, ref_stack: ref_stack, ref_chain: ref_chain)
        end

        node.each_with_object({}) do |(k, v), out|
          out[k] = dereference(v, current_document: current_document, ref_stack: ref_stack, ref_chain: ref_chain)
        end
      when Array
        node.map { |v| dereference(v, current_document: current_document, ref_stack: ref_stack, ref_chain: ref_chain) }
      else
        node
      end
    end

    def dereference_ref(node, current_document:, ref_stack:, ref_chain:)
      ref = node.fetch("$ref")
      key = [current_document.absolute_path, ref]

      if ref_stack.include?(key)
        chain = (ref_chain + [key]).map { |(file, r)| "#{file}:#{r}" }.join(" -> ")
        raise CircularReferenceError, "Circular $ref detected: #{chain}"
      end

      overlay = node.dup
      overlay.delete("$ref")

      ref_stack.add(key)
      ref_chain.push(key)

      resolved = @ref_resolver.resolve(ref, from_document: current_document)

      resolved_fragment =
        dereference(
          resolved.fragment,
          current_document: resolved.document,
          ref_stack: ref_stack,
          ref_chain: ref_chain
        )

      overlay_fragment =
        dereference(
          overlay,
          current_document: current_document,
          ref_stack: ref_stack,
          ref_chain: ref_chain
        )

      merged =
        if resolved_fragment.is_a?(Hash) && overlay_fragment.is_a?(Hash)
          resolved_fragment.deep_merge(overlay_fragment)
        else
          overlay_fragment.presence || resolved_fragment
        end

      ref_chain.pop
      ref_stack.delete(key)

      merged
    end

    def dereference_all_of(node, current_document:, ref_stack:, ref_chain:)
      base = node.dup
      all_of = Array(base.delete("allOf"))

      merged = {}
      all_of.each do |subschema|
        resolved = dereference(subschema, current_document: current_document, ref_stack: ref_stack, ref_chain: ref_chain)
        next if resolved.blank?

        merged =
          if merged.is_a?(Hash) && resolved.is_a?(Hash)
            merged.deep_merge(resolved)
          else
            resolved
          end
      end

      base_resolved = dereference(base, current_document: current_document, ref_stack: ref_stack, ref_chain: ref_chain)

      if merged.is_a?(Hash) && base_resolved.is_a?(Hash)
        merged.deep_merge(base_resolved)
      else
        base_resolved.presence || merged
      end
    end
  end
end
