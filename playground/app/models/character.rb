# frozen_string_literal: true

# Character model representing imported character cards.
#
# Supports both CCv2 and CCv3 formats. The `data` jsonb column stores the
# complete spec data, while commonly queried fields are extracted to
# dedicated columns for performance.
#
# @example Import a character
#   result = CharacterImport::Detector.import(file)
#   character = result.character
#
# @example Query characters
#   Character.ready.where("tags @> ?", '["fantasy"]')
#
class Character < ApplicationRecord
  include Portraitable

  # Status values for the character lifecycle
  STATUSES = %w[pending ready failed deleting].freeze

  # CCv3 asset kinds
  ASSET_KINDS = %w[icon emotion background user_icon other].freeze

  # Associations
  has_many :character_assets, dependent: :destroy
  has_many :character_uploads, dependent: :nullify

  # Space/chat associations
  # Note: Using nullify to preserve chat history when character is deleted
  has_many :space_memberships, dependent: :nullify
  has_many :spaces, through: :space_memberships

  # Character portrait image (extracted from PNG or CCv3 icon with name="main")
  # Standard size: 400x600 (2:3 aspect ratio)
  has_one_attached :portrait do |attachable|
    attachable.variant :standard, resize_to_limit: [400, 600]
  end

  # Validations
  validates :name, presence: true
  validates :spec_version, inclusion: { in: [2, 3] }, allow_nil: true
  validates :spec_version, presence: true, unless: -> { pending? || status == "failed" }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :data, presence: true, unless: -> { pending? || status == "failed" }

  # Scopes
  scope :ready, -> { where(status: "ready") }
  scope :pending, -> { where(status: "pending") }
  scope :failed, -> { where(status: "failed") }
  scope :ordered, -> { order("LOWER(name)") }
  scope :by_spec_version, ->(version) { where(spec_version: version) }
  scope :with_tag, ->(tag) { where("tags @> ARRAY[?]::varchar[]", tag) }

  # Callbacks
  before_validation :extract_searchable_fields, if: :data_changed?

  # Mark the character as ready for use.
  #
  # @return [Boolean] true if successfully saved
  def mark_ready!
    update!(status: "ready")
  end

  # Mark the character as failed with an error message.
  #
  # @param message [String] error description
  # @return [Boolean] true if successfully saved
  def mark_failed!(message = nil)
    # Store error in data extensions for debugging
    if message.present?
      self.data = (data || {}).merge("_import_error" => message)
    end
    self.status = "failed"
    save!
  end

  # Mark the character for deletion.
  #
  # @return [Boolean] true if successfully saved
  def mark_deleting!
    update!(status: "deleting")
  end

  # Check if character import is pending.
  #
  # @return [Boolean]
  def pending?
    status == "pending"
  end

  # Check if character is ready for use.
  #
  # @return [Boolean]
  def ready?
    status == "ready"
  end

  # Check if character is CCv3.
  #
  # @return [Boolean]
  def v3?
    spec_version == 3
  end

  # Check if character is CCv2.
  #
  # @return [Boolean]
  def v2?
    spec_version == 2
  end

  # Get the first message (greeting).
  #
  # @return [String, nil]
  def first_mes
    data["first_mes"]
  end

  # Get the description.
  #
  # @return [String, nil]
  def description
    data["description"]
  end

  # Get the scenario.
  #
  # @return [String, nil]
  def scenario
    data["scenario"]
  end

  # Get the system prompt.
  #
  # @return [String, nil]
  def system_prompt
    data["system_prompt"]
  end

  # Get alternate greetings.
  #
  # @return [Array<String>]
  def alternate_greetings
    data["alternate_greetings"] || []
  end

  # Get group-only greetings (CCv3).
  #
  # @return [Array<String>]
  def group_only_greetings
    data["group_only_greetings"] || []
  end

  # Get the character book (lorebook).
  #
  # @return [Hash, nil]
  def character_book
    data["character_book"]
  end

  # Get creator notes.
  #
  # @return [String, nil]
  def creator_notes
    data["creator_notes"]
  end

  # Get the creator.
  #
  # @return [String, nil]
  def creator
    data["creator"]
  end

  # Get the character version.
  #
  # @return [String, nil]
  def character_version
    data["character_version"]
  end

  # Get CCv3 assets array.
  #
  # @return [Array<Hash>, nil]
  def assets
    data["assets"]
  end

  # Convert to TavernKit::Character for prompt building.
  #
  # @return [TavernKit::Character]
  def to_tavern_kit_character
    TavernKit::CharacterCard.load_hash(export_card_hash)
  end

  # Export as a character card hash (for JSON export).
  #
  # @param version [Integer] 2 or 3, defaults to source version
  # @return [Hash]
  def export_card_hash(version: spec_version)
    if version == 3
      {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => data,
      }
    else
      {
        "spec" => "chara_card_v2",
        "spec_version" => "2.0",
        "data" => data.except("group_only_greetings", "assets", "nickname",
                              "creator_notes_multilingual", "source",
                              "creation_date", "modification_date"),
      }
    end
  end

  # Export as JSON string.
  #
  # @param version [Integer] 2 or 3, defaults to source version
  # @return [String] JSON-encoded character card
  def export_json(version: spec_version)
    CharacterExport::JsonExporter.new(self, version: version).call
  end

  # Export as PNG with embedded metadata.
  #
  # @param format [Symbol] :both, :v2_only, or :v3_only
  # @return [String] PNG binary content
  # @raise [CharacterExport::ExportError] if portrait not attached
  def export_png(format: :both)
    CharacterExport::PngExporter.new(self, format: format).call
  end

  # Export as CharX (ZIP archive with assets).
  #
  # @return [String] ZIP binary content
  def export_charx
    CharacterExport::CharxExporter.new(self).call
  end

  # Export to a file with auto-detected format.
  #
  # @param path [String] output file path (.json, .png, or .charx)
  # @param options [Hash] export options (version:, format:)
  # @return [Integer] bytes written
  def export_to_file(path, **options)
    ext = File.extname(path).downcase

    content = case ext
    when ".json"
                export_json(version: options[:version] || spec_version)
    when ".png"
                export_png(format: options[:format] || :both)
    when ".charx"
                export_charx
    else
                raise ArgumentError, "Unsupported export format: #{ext}"
    end

    File.binwrite(path, content)
  end

  private

  # Extract commonly searched fields from data for query performance.
  def extract_searchable_fields
    return if data.blank?

    self.name = data["name"] if data["name"].present?
    self.nickname = data["nickname"]
    self.personality = data["personality"]
    self.tags = data["tags"] || []
    self.supported_languages = extract_supported_languages
  end

  # Extract supported language codes from creator_notes_multilingual.
  #
  # @return [Array<String>]
  def extract_supported_languages
    multilingual = data["creator_notes_multilingual"]
    return [] unless multilingual.is_a?(Hash)

    multilingual.keys
  end
end
