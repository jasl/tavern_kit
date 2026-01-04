# frozen_string_literal: true

# Key-value settings storage with encrypted values and caching.
#
# Used to store sensitive configuration like API keys securely in the database,
# with Rails.cache for performance optimization.
#
# @example Get a setting
#   Setting.get("llm.api_key")
#   # => "sk-..."
#
# @example Set a setting
#   Setting.set("llm.api_key", "sk-new-key")
#
# @example Get multiple settings with prefix
#   Setting.get_all("llm.")
#   # => { "llm.endpoint" => "https://api.openai.com", "llm.api_key" => "sk-..." }
#
# @example Cache behavior
#   Setting.get("key")       # Cache miss, queries DB
#   Setting.get("key")       # Cache hit, no DB query
#   Setting.set("key", "v")  # Updates DB and invalidates cache
#   Setting.get("key")       # Cache miss, queries DB again
#
class Setting < ApplicationRecord
  encrypts :value

  validates :key, presence: true, uniqueness: true

  # Cache configuration
  CACHE_PREFIX = "settings"
  CACHE_VERSION = "v1"
  CACHE_TTL = 1.hour
  CACHE_ALL_PREFIX_TTL = 5.minutes

  # Callbacks to invalidate cache on changes
  after_commit :invalidate_cache, on: %i[create update destroy]

  class << self
    # Get a setting value by key (with caching).
    #
    # @param key [String] setting key
    # @param default [Object] default value if not found
    # @return [String, nil] setting value or default
    def get(key, default = nil)
      cache_key = build_cache_key(key)

      # Intentionally cache nil values as well (negative caching). This avoids
      # repeated database queries for missing keys that are requested often.
      # Cache is invalidated automatically when a Setting record is created,
      # updated, or destroyed (see after_commit callback).
      value = Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        find_by(key: key)&.value
      end

      value.nil? ? default : value
    end

    # Set a setting value by key (invalidates cache).
    #
    # @param key [String] setting key
    # @param value [String] setting value (will be encrypted)
    # @return [Setting] the created or updated setting
    def set(key, value)
      setting = find_or_initialize_by(key: key)
      setting.value = value
      setting.save!
      setting
    end

    # Delete a setting by key (invalidates cache).
    #
    # @param key [String] setting key
    # @return [Boolean] true if deleted, false if not found
    def delete(key)
      setting = find_by(key: key)
      return false unless setting

      setting.destroy
      true
    end

    # Check if a setting exists (with caching).
    #
    # @param key [String] setting key
    # @return [Boolean] true if exists
    def exists?(key)
      get(key).present?
    end

    # Get all settings matching a key prefix (with caching).
    #
    # @param prefix [String] key prefix (e.g., "llm.")
    # @return [Hash] hash of key => value pairs
    def get_all(prefix = "")
      cache_key = build_prefix_cache_key(prefix)

      Rails.cache.fetch(cache_key, expires_in: CACHE_ALL_PREFIX_TTL) do
        where("key LIKE ?", "#{sanitize_sql_like(prefix)}%")
          .each_with_object({}) do |setting, hash|
            hash[setting.key] = setting.value
          end
      end
    end

    # Set multiple settings at once (batch operation).
    #
    # @param hash [Hash] hash of key => value pairs
    # @return [Array<Setting>] array of created/updated settings
    def set_all(hash)
      transaction do
        hash.map { |key, value| set(key, value) }
      end
    end

    # Delete all settings matching a key prefix.
    #
    # @param prefix [String] key prefix
    # @return [Integer] number of deleted settings
    def delete_all_with_prefix(prefix)
      settings = where("key LIKE ?", "#{sanitize_sql_like(prefix)}%")
      count = settings.count
      settings.destroy_all
      invalidate_prefix_cache(prefix)
      count
    end

    # Get LLM settings as a hash with symbolized keys (without prefix).
    #
    # @return [Hash] LLM settings hash
    def llm_settings
      get_all("llm.").transform_keys { |k| k.delete_prefix("llm.").to_sym }
    end

    # Set LLM settings from a hash.
    #
    # @param settings [Hash] settings hash with symbol or string keys
    # @return [Array<Setting>] array of created/updated settings
    def set_llm_settings(settings)
      transaction do
        settings.filter_map do |key, value|
          next if value.blank?

          set("llm.#{key}", value.to_s)
        end
      end.tap { invalidate_prefix_cache("llm.") }
    end

    # Clear all cached settings.
    #
    # @return [void]
    def clear_cache
      Rails.cache.delete_matched("#{CACHE_PREFIX}/*")
    end

    # Build cache key for a single setting.
    #
    # @param key [String] setting key
    # @return [String] cache key
    def build_cache_key(key)
      "#{CACHE_PREFIX}/#{CACHE_VERSION}/key/#{key}"
    end

    # Build cache key for prefix queries.
    #
    # @param prefix [String] key prefix
    # @return [String] cache key
    def build_prefix_cache_key(prefix)
      "#{CACHE_PREFIX}/#{CACHE_VERSION}/prefix/#{prefix.presence || '_all_'}"
    end

    # Invalidate cache for a specific key.
    #
    # @param key [String] setting key
    # @return [void]
    def invalidate_key_cache(key)
      Rails.cache.delete(build_cache_key(key))
      # Also invalidate any prefix caches that might include this key
      invalidate_related_prefix_caches(key)
    end

    # Invalidate cache for a prefix.
    #
    # @param prefix [String] key prefix
    # @return [void]
    def invalidate_prefix_cache(prefix)
      Rails.cache.delete(build_prefix_cache_key(prefix))
      # Also invalidate the "all" cache
      Rails.cache.delete(build_prefix_cache_key(""))
    end

    private

    # Invalidate prefix caches that might contain the given key.
    #
    # @param key [String] setting key
    # @return [void]
    def invalidate_related_prefix_caches(key)
      # Invalidate all possible prefix caches for this key
      # e.g., for "llm.api.key", invalidate "llm.", "llm.api.", and ""
      parts = key.split(".")
      prefixes = [""]
      parts[0..-2].each_with_index do |_, i|
        prefixes << "#{parts[0..i].join('.')}."
      end

      prefixes.each do |prefix|
        Rails.cache.delete(build_prefix_cache_key(prefix))
      end
    end
  end

  private

  # Invalidate cache when this setting is changed.
  def invalidate_cache
    self.class.invalidate_key_cache(key)

    # If key was changed, also invalidate the old key
    if saved_change_to_key? && key_before_last_save.present?
      self.class.invalidate_key_cache(key_before_last_save)
    end
  end
end
