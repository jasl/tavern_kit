# frozen_string_literal: true

require "easy_talk"

module TavernKit
  class Character
    # Schema for V3 Asset objects.
    #
    # Assets represent embedded resources (images, audio, etc.) in a character card.
    # URI schemes supported by CCv3:
    # - embeded://path/to/asset.png (embedded in CHARX)
    # - ccdefault: (default asset for the type)
    # - __asset:N (legacy PNG chunk reference)
    # - data: (inline data URI)
    # - http(s):// (external URL)
    #
    # @see https://github.com/kwaroran/character-card-spec-v3
    class AssetSchema
      include EasyTalk::Schema

      define_schema do
        title "Character Card Asset"
        description "An embedded or referenced asset in a character card (V3)"

        # Asset type determines how it's used:
        # - icon: character portrait/avatar
        # - background: chat background
        # - user_icon: user avatar override
        # - emotion: character expression/emotion sprite
        # - Other custom types prefixed with x_ are allowed
        property :type, String, description: "Asset type (icon, background, user_icon, emotion, or custom x_* type)"

        # URI to the asset content
        property :uri, String, description: "Asset URI (embeded://, ccdefault:, __asset:N, data:, or http(s)://)"

        # Unique identifier within the character
        # For icon type: "main" is required for the primary icon
        # For emotion type: identifies the emotion (happy, sad, angry, etc.)
        property :name, String, description: "Asset identifier within the character"

        # File extension without the dot (png, jpg, webp, etc.)
        # Should be lowercase. Can be "unknown" for unknown formats.
        property :ext, String, description: "File extension without dot (e.g., png, jpg, webp)"
      end

      # Check if this is the main icon
      def main_icon?
        type == "icon" && name == "main"
      end

      # Check if this is the main background
      def main_background?
        type == "background" && name == "main"
      end

      # Check if this is an embedded asset (in CHARX)
      def embedded?
        uri&.start_with?("embeded://")
      end

      # Check if this uses the default placeholder
      def default?
        uri == "ccdefault:"
      end

      # Check if this is a data URI
      def data_uri?
        uri&.start_with?("data:")
      end

      # Check if this is an external URL
      def external_url?
        uri&.match?(%r{\Ahttps?://}i)
      end

      # Extract the path from an embedded URI
      # @return [String, nil] the path without "embeded://" prefix
      def embedded_path
        return nil unless embedded?

        uri.sub(%r{\Aembeded://}, "")
      end
    end
  end
end
