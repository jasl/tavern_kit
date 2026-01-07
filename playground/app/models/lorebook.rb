# frozen_string_literal: true

# Standalone World Info / Lorebook model.
#
# Represents a collection of lore entries that can be attached to spaces
# and activated during prompt generation based on keyword matching.
#
# @example Create a lorebook
#   lorebook = Lorebook.create!(name: "Fantasy World")
#   lorebook.entries.create!(uid: "1", keys: ["dragon"], content: "Dragons are...")
#
class Lorebook < ApplicationRecord
  include Lockable
  include Publishable

  # Associations
  belongs_to :user, optional: true
  has_many :entries,
           class_name: "LorebookEntry",
           dependent: :destroy,
           inverse_of: :lorebook
  has_many :space_lorebooks, dependent: :destroy
  has_many :spaces, through: :space_lorebooks
  has_many :character_lorebooks, dependent: :destroy
  has_many :characters, through: :character_lorebooks

  # Validations
  validates :name, presence: true
  validates :scan_depth, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :token_budget, numericality: { greater_than: 0 }, allow_nil: true

  # Scopes
  scope :ordered, -> { order("LOWER(name)") }
  scope :with_entries_count, lambda {
    left_joins(:entries)
      .group(:id)
      .select("lorebooks.*, COUNT(lorebook_entries.id) AS entries_count")
  }

  class << self
    def accessible_to(user, now: Time.current)
      accessible_to_system_or_owned(user, owner_column: :user_id, now: now)
    end
  end

  # Convert to TavernKit::Lore::Book for prompt building.
  #
  # @param source [Symbol] source identifier (:global, :character, etc.)
  # @return [TavernKit::Lore::Book]
  def to_lore_book(source: :global)
    TavernKit::Lore::Book.new(
      name: name,
      description: description,
      scan_depth: scan_depth,
      token_budget: token_budget,
      recursive_scanning: recursive_scanning,
      entries: entries.enabled.ordered.map { |e| e.to_lore_entry(source: source, book_name: name) },
      extensions: settings || {},
      source: source
    )
  end

  # Import from SillyTavern World Info JSON.
  #
  # @param json_data [Hash] parsed JSON data
  # @param name_override [String, nil] optional name override
  # @return [Lorebook]
  def self.import_from_json(json_data, name_override: nil)
    data = json_data.is_a?(String) ? JSON.parse(json_data) : json_data
    data = data.with_indifferent_access

    lorebook = new(
      name: name_override.presence || data[:name] || "Imported Lorebook",
      description: data[:description],
      scan_depth: data[:scanDepth] || data[:scan_depth],
      token_budget: data[:tokenBudget] || data[:token_budget],
      recursive_scanning: coerce_bool(data[:recursiveScanning] || data[:recursive_scanning]),
      settings: data[:extensions] || {}
    )

    entries_data = data[:entries]
    entries_list = case entries_data
    when Array then entries_data.each_with_index.map { |e, i| [e[:uid] || e[:id] || i + 1, e] }
    when Hash
      # Sort entries: numeric keys first (by value), then non-numeric (alphabetically)
      # Use array comparison to avoid ArgumentError when mixing Integer/String
      entries_data.to_a.sort_by do |k, _|
        key_str = k.to_s
        if key_str.match?(/^\d+$/)
          [0, key_str.to_i]  # Numeric keys: sort first, by integer value
        else
          [1, key_str]       # Non-numeric keys: sort after, alphabetically
        end
      end
    else []
    end

    entries_list.each_with_index do |(uid, entry_data), index|
      lorebook.entries.build(
        LorebookEntry.attributes_from_json(entry_data, uid: uid.to_s, position_index: index)
      )
    end

    lorebook
  end

  # Export to SillyTavern-compatible JSON hash.
  #
  # @return [Hash]
  def export_to_json
    {
      name: name,
      description: description,
      scanDepth: scan_depth,
      tokenBudget: token_budget,
      recursiveScanning: recursive_scanning,
      extensions: settings || {},
      entries: entries.ordered.each_with_object({}) do |entry, hash|
        hash[entry.uid] = entry.export_to_json
      end,
    }
  end

  def self.coerce_bool(value)
    return false if value.nil?
    return value if value == true || value == false

    %w[1 true yes y on].include?(value.to_s.strip.downcase)
  end
  private_class_method :coerce_bool
end
