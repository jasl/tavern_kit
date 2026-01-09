# frozen_string_literal: true

require "tavern_kit/character/schema"

# Character model representing imported character cards.
#
# Supports both CCv2 and CCv3 formats. The `data` jsonb column stores the
# complete spec data as a TavernKit::Character::Schema object, while commonly
# queried fields are extracted to dedicated columns for performance.
#
# @example Import a character
#   result = CharacterImport::Detector.import(file)
#   character = result.character
#
# @example Query characters
#   Character.ready.where("tags @> ?", '["fantasy"]')
#
# @example Access schema properties
#   character.data.description  # => "A brave knight..."
#   character.data.personality  # => "Bold and courageous"
#
class Character < ApplicationRecord
  include Duplicatable
  include Lockable
  include Portraitable
  include Publishable

  # Serialize data column as TavernKit::Character::Schema
  # DB constraint guarantees data is always a JSON object (Hash)
  serialize :data, coder: EasyTalkCoder.new(TavernKit::Character::Schema)

  # Serialize authors_note_settings as ConversationSettings::AuthorsNoteSettings schema
  # This contains prompt building settings for author's notes at the character level
  serialize :authors_note_settings, coder: EasyTalkCoder.new(ConversationSettings::AuthorsNoteSettings)

  # Status values for the character lifecycle
  STATUSES = %w[pending ready failed deleting].freeze

  # Visibility values
  VISIBILITIES = %w[private public].freeze

  # CCv3 asset kinds
  ASSET_KINDS = %w[icon emotion background user_icon other].freeze

  # Associations
  belongs_to :user, optional: true
  has_many :character_assets, dependent: :destroy
  has_many :character_uploads, dependent: :nullify

  # Space/chat associations
  # Note: Using nullify to preserve chat history when character is deleted
  has_many :space_memberships, dependent: :nullify
  has_many :spaces, through: :space_memberships

  # Linked lorebooks (ST: "Link to World Info" and "Extra World Info")
  has_many :character_lorebooks, dependent: :destroy
  has_many :lorebooks, through: :character_lorebooks

  # Character portrait image (extracted from PNG or CCv3 icon with name="main")
  # Standard size: 400x600 (2:3 aspect ratio)
  has_one_attached :portrait do |attachable|
    attachable.variant :standard, resize_to_limit: [400, 600]
  end

  # Validations
  validates :name, presence: true
  validates :spec_version, inclusion: { in: [2, 3] }, allow_nil: true
  validates :spec_version, presence: true, unless: -> { pending? || failed? }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :visibility, inclusion: { in: VISIBILITIES }
  validate :data_must_have_name, unless: -> { pending? || failed? }

  # Enums (use suffix to avoid conflict with Ruby's built-in private? method)
  enum :visibility, VISIBILITIES.index_by(&:itself), default: "private", suffix: true

  # Scopes
  scope :ready, -> { where(status: "ready") }
  scope :pending, -> { where(status: "pending") }
  scope :failed, -> { where(status: "failed") }
  scope :ordered, -> { order("LOWER(name)") }
  scope :by_spec_version, ->(version) { where(spec_version: version) }
  scope :with_tag, ->(tag) { where("tags @> ARRAY[?]::varchar[]", tag) }

  class << self
    def accessible_to(user)
      accessible_to_system_or_owned(user, owner_column: :user_id)
    end
  end

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
    # Store error in data.extensions for debugging
    if message.present?
      current_hash = data.present? ? JSON.parse(data.to_json) : {}
      current_hash["extensions"] ||= {}
      current_hash["extensions"]["_import_error"] = message
      self.data = TavernKit::Character::Schema.new(current_hash.deep_symbolize_keys)
    end
    self.status = "failed"
    save!
  end

  # Get the import error message (if any)
  #
  # @return [String, nil]
  def import_error
    data&.extensions&.dig(:_import_error) || data&.extensions&.dig("_import_error")
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

  # Check if character import failed.
  #
  # @return [Boolean]
  def failed?
    status == "failed"
  end

  # Check if character is being deleted.
  #
  # @return [Boolean]
  def deleting?
    status == "deleting"
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

  # ──────────────────────────────────────────────────────────────────
  # Schema Property Accessors
  # These delegate to the TavernKit::Character::Schema data object
  # ──────────────────────────────────────────────────────────────────

  # Get the first message (greeting).
  #
  # @return [String, nil]
  def first_mes
    data&.first_mes
  end

  # Get the description.
  #
  # @return [String, nil]
  def description
    data&.description
  end

  # Get the scenario.
  #
  # @return [String, nil]
  def scenario
    data&.scenario
  end

  # Get the personality.
  #
  # @return [String, nil]
  def data_personality
    data&.personality
  end

  # Get the system prompt.
  #
  # @return [String, nil]
  def system_prompt
    data&.system_prompt
  end

  # Get post history instructions (jailbreak/PHI).
  #
  # @return [String, nil]
  def post_history_instructions
    data&.post_history_instructions
  end

  # Get example dialogue.
  #
  # @return [String, nil]
  def mes_example
    data&.mes_example
  end

  # Get alternate greetings.
  #
  # @return [Array<String>]
  def alternate_greetings
    data&.alternate_greetings || []
  end

  # Get group-only greetings (CCv3).
  #
  # @return [Array<String>]
  def group_only_greetings
    data&.group_only_greetings || []
  end

  # Get the character book (lorebook).
  #
  # @return [TavernKit::Character::CharacterBookSchema, nil]
  def character_book
    data&.character_book
  end

  # ──────────────────────────────────────────────────────────────────
  # Linked Lorebooks (ST: "Link to World Info" and "Extra World Info")
  # ──────────────────────────────────────────────────────────────────

  # Get the primary linked lorebook (if any).
  # This is equivalent to ST's "Link to World Info" feature.
  #
  # @return [Lorebook, nil]
  def primary_lorebook
    character_lorebooks.primary.enabled.first&.lorebook
  end

  # Get all additional linked lorebooks, ordered by priority.
  # This is equivalent to ST's "Extra World Info" feature.
  #
  # @return [Array<Lorebook>]
  def additional_lorebooks
    character_lorebooks.additional.enabled.by_priority.includes(:lorebook).map(&:lorebook)
  end

  # Get all linked lorebooks (primary + additional), ordered appropriately.
  #
  # @return [Array<Lorebook>]
  def all_linked_lorebooks
    primary = primary_lorebook
    additional = additional_lorebooks

    primary ? [primary] + additional : additional
  end

  # Get creator notes.
  #
  # @return [String, nil]
  def creator_notes
    data&.creator_notes
  end

  # Get the creator.
  #
  # @return [String, nil]
  def creator
    data&.creator
  end

  # Get the character version.
  #
  # @return [String, nil]
  def character_version
    data&.character_version
  end

  # Get CCv3 assets array.
  #
  # @return [Array<TavernKit::Character::AssetSchema>, nil]
  def assets
    data&.assets
  end

  # ──────────────────────────────────────────────────────────────────
  # Author's Note Settings
  # ──────────────────────────────────────────────────────────────────

  # Get the effective Author's Note settings for this character.
  # Returns a default AuthorsNoteSettings if no settings are configured.
  #
  # @return [ConversationSettings::AuthorsNoteSettings]
  def effective_authors_note_settings
    authors_note_settings || ConversationSettings::AuthorsNoteSettings.new
  end

  # Get the character's Author's Note content.
  #
  # @return [String, nil]
  def authors_note
    effective_authors_note_settings.authors_note.presence
  end

  # Check if the character's Author's Note is enabled.
  #
  # @return [Boolean]
  def authors_note_enabled?
    effective_authors_note_settings.use_character_authors_note == true &&
      authors_note.present?
  end

  # Get the character's Author's Note position (in_chat, in_prompt, before_prompt).
  #
  # @return [String]
  def authors_note_position
    effective_authors_note_settings.authors_note_position || "in_chat"
  end

  # Get the character's Author's Note depth.
  #
  # @return [Integer]
  def authors_note_depth
    effective_authors_note_settings.authors_note_depth || 4
  end

  # Get the character's Author's Note role.
  #
  # @return [String]
  def authors_note_role
    effective_authors_note_settings.authors_note_role || "system"
  end

  # Get how the character AN combines with space AN (replace, before, after).
  #
  # @return [String]
  def character_authors_note_position
    effective_authors_note_settings.character_authors_note_position || "replace"
  end

  # Export as a character card hash (for JSON export).
  #
  # @param version [Integer] 2 or 3, defaults to source version
  # @return [Hash]
  def export_card_hash(version: spec_version)
    # Convert Schema to hash with string keys for JSON export
    data_hash = data&.to_h&.deep_stringify_keys || {}

    if version == 3
      {
        "spec" => "chara_card_v3",
        "spec_version" => "3.0",
        "data" => data_hash,
      }
    else
      {
        "spec" => "chara_card_v2",
        "spec_version" => "2.0",
        "data" => data_hash.except("group_only_greetings", "assets", "nickname",
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

  # Custom validation: data must have at least a name to be considered valid
  def data_must_have_name
    if data.blank? || !data.respond_to?(:name) || data.name.blank?
      errors.add(:data, "can't be blank")
    end
  end

  # Extract commonly searched fields from data for query performance.
  def extract_searchable_fields
    return if data.blank?

    self.name = data.name if data.name.present?
    self.nickname = data.nickname
    self.personality = data.personality
    self.tags = data.tags || []
    self.supported_languages = extract_supported_languages
  end

  # Extract supported language codes from creator_notes_multilingual.
  #
  # @return [Array<String>]
  def extract_supported_languages
    multilingual = data&.creator_notes_multilingual
    return [] unless multilingual.respond_to?(:to_h)

    multilingual.to_h.keys.map(&:to_s)
  end

  # Attributes for creating a copy of this character.
  # Used by Duplicatable concern.
  #
  # @return [Hash] attributes for the copy
  def copy_attributes
    copy_name = "#{name} (Copy)"

    # Deep copy data and update the name
    # Use deep_stringify_keys to ensure consistent string keys (avoid duplicate key warnings)
    data_copy = data&.to_h&.deep_stringify_keys&.deep_dup || {}
    data_copy["name"] = copy_name

    {
      name: copy_name,
      nickname: nickname,
      spec_version: spec_version,
      tags: tags.dup,
      personality: personality,
      supported_languages: supported_languages.dup,
      data: data_copy,
      authors_note_settings: authors_note_settings&.to_h&.deep_dup,
      status: "ready",
      visibility: "private",
      # Note: user_id is NOT copied - should be set via override
      # Note: locked_at is NOT copied - copies start fresh
      # Note: visibility is explicitly set to private - copies start as drafts
      # Note: file_sha256 is NOT copied - this is a new record
    }
  end

  # Copy portrait and assets after the character copy is saved.
  # Called by Duplicatable concern.
  #
  # Reuses existing blobs instead of creating new copies.
  # This is safe because asset files are immutable (only add/delete, never edit).
  # ActiveStorage handles reference counting - blob is only deleted when all
  # attachments referencing it are removed.
  #
  # @param copy [Character] the newly created character copy
  def after_copy(copy)
    # Copy portrait (reuse blob)
    copy.portrait.attach(portrait.blob) if portrait.attached?

    # Copy character assets (reuse blobs)
    # This is efficient: we only create new CharacterAsset records pointing to the same blobs
    character_assets.find_each do |asset|
      copy.character_assets.create!(
        blob: asset.blob,
        name: asset.name,
        kind: asset.kind,
        ext: asset.ext,
        content_sha256: asset.content_sha256
      )
    end
  end
end
