# frozen_string_literal: true

# CharacterAsset stores metadata for character assets (images, backgrounds, etc.).
#
# Uses ActiveStorage for actual file storage, with this model tracking
# asset-specific metadata like kind, name, and content hash for deduplication.
#
# @example Access character assets
#   character.character_assets.icons
#   character.character_assets.find_by(name: "happy")
#
class CharacterAsset < ApplicationRecord
  # Asset kind values from CCv3 spec
  KINDS = %w[icon emotion background user_icon other].freeze

  # Associations
  belongs_to :character
  belongs_to :blob, class_name: "ActiveStorage::Blob"

  # Validations
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :name, presence: true, uniqueness: { scope: :character_id }

  # Scopes
  scope :icons, -> { where(kind: "icon") }
  scope :emotions, -> { where(kind: "emotion") }
  scope :backgrounds, -> { where(kind: "background") }
  scope :user_icons, -> { where(kind: "user_icon") }

  # Get the URL for this asset.
  #
  # @return [String] URL to the blob
  def url
    Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
  end

  # Get the signed URL for this asset (for direct download).
  #
  # @param expires_in [ActiveSupport::Duration] expiration time
  # @return [String] signed URL
  def signed_url(expires_in: 1.hour)
    blob.url(expires_in: expires_in)
  end

  # Check if this is the main icon.
  #
  # @return [Boolean]
  def main_icon?
    kind == "icon" && name == "main"
  end
end
