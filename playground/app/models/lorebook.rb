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
  include Duplicatable
  include Lockable
  include Publishable

  # Associations
  belongs_to :user, optional: true, counter_cache: true
  has_many :entries,
           class_name: "LorebookEntry",
           dependent: :destroy,
           inverse_of: :lorebook
  has_many :space_lorebooks, dependent: :destroy
  has_many :spaces, through: :space_lorebooks
  has_many :conversation_lorebooks, dependent: :destroy
  has_many :conversations, through: :conversation_lorebooks

  # Visibility values
  VISIBILITIES = %w[private public].freeze

  # Validations
  validates :name, presence: true
  validates :scan_depth, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :token_budget, numericality: { greater_than: 0 }, allow_nil: true
  validates :visibility, inclusion: { in: VISIBILITIES }

  # Enums (use suffix to avoid conflict with Ruby's built-in private? method)
  enum :visibility, VISIBILITIES.index_by(&:itself), default: "private", suffix: true

  # Scopes
  scope :ordered, -> { order("LOWER(name)") }
  # Note: entries_count is now a counter_cache column, no need for with_entries_count scope

  after_commit :invalidate_name_resolver_cache, on: %i[create update destroy]

  class << self
    def accessible_to(user)
      accessible_to_system_or_owned(user, owner_column: :user_id)
    end
  end

  # Convert to TavernKit::Lore::Book for prompt building.
  #
  # @param source [Symbol] source identifier (:global, :character, etc.)
  # @return [TavernKit::Lore::Book]
  def to_lore_book(source: :global)
    entry_records =
      if entries.loaded?
        entries
          .select(&:enabled?)
          .sort_by { |e| [e.position_index.to_i, e.insertion_order.to_i] }
      else
        entries.enabled.ordered.to_a
      end

    TavernKit::Lore::Book.new(
      name: name,
      description: description,
      scan_depth: scan_depth,
      token_budget: token_budget,
      recursive_scanning: recursive_scanning,
      entries: entry_records.map { |e| e.to_lore_entry(source: source, book_name: name) },
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

  # Approximate number of Characters referencing this lorebook by name.
  #
  # Links are name-based (`extensions.world` / `extensions.extra_worlds`) so we
  # count by the resolved *name*, using extracted Character columns.
  #
  # This is cached and intentionally not strongly consistent.
  #
  # @param user [User, nil] scope count to a user's accessible Characters
  # @param ttl [ActiveSupport::Duration]
  # @return [Integer]
  def approximate_character_usage_count(user: nil, ttl: 30.minutes)
    cache_key = "lorebooks:usage_count:v2:u#{user&.id || 'anon'}:#{id}:#{name}"

    Rails.cache.fetch(cache_key, expires_in: ttl) do
      base =
        if user
          # Characters are either system-owned (user_id: nil) or owned by a user.
          # Scope usage counts to characters that the given user can actually use.
          Character.where(user_id: [nil, user.id])
        else
          Character.where(user_id: nil)
        end

      base
        .where(world_name: name)
        .or(base.where("? = ANY(extra_world_names)", name))
        .count
    end
  end

  def self.coerce_bool(value)
    return false if value.nil?
    return value if value == true || value == false

    %w[1 true yes y on].include?(value.to_s.strip.downcase)
  end
  private_class_method :coerce_bool

  private

  def invalidate_name_resolver_cache
    # Only user-owned lorebooks affect that user's soft-link resolution.
    # Global/system lorebooks (user_id: nil) are not user-creatable.
    return unless user_id.present?

    affected_user_ids =
      [user_id, previous_changes.dig("user_id", 0), previous_changes.dig("user_id", 1)]
        .compact
        .uniq

    affected_names =
      [name, previous_changes.dig("name", 0), previous_changes.dig("name", 1)]
        .compact
        .map { |n| n.to_s.strip }
        .reject(&:empty?)
        .uniq

    return if affected_user_ids.empty? || affected_names.empty?

    resolver = Lorebooks::NameResolver.new

    affected_user_ids.each do |uid|
      user = self.user if self.user&.id == uid
      user ||= User.find_by(id: uid)
      next unless user

      affected_names.each { |n| resolver.invalidate(user: user, name: n) }
    end
  end

  # Attributes for creating a copy of this lorebook.
  # Used by Duplicatable concern.
  #
  # @return [Hash] attributes for the copy
  def copy_attributes
    {
      name: "#{name} (Copy)",
      description: description,
      scan_depth: scan_depth,
      token_budget: token_budget,
      recursive_scanning: recursive_scanning,
      settings: settings&.deep_dup,
      visibility: "private",
      # Note: user_id is NOT copied - copies are always user-owned
      # Note: locked_at is NOT copied - copies start fresh
      # Note: visibility is explicitly set to private - copies start as drafts
    }
  end

  # Copy entries after the lorebook copy is saved.
  # Called by Duplicatable concern.
  #
  # @param copy [Lorebook] the newly created lorebook copy
  def after_copy(copy)
    entries.ordered.each do |entry|
      copy.entries.create!(
        entry.attributes.except("id", "lorebook_id", "created_at", "updated_at")
      )
    end
  end
end
