# frozen_string_literal: true

module Lorebooks
  # Resolve a Lorebook by its name (soft link), with Rails.cache acceleration.
  #
  # This matches SillyTavern semantics:
  # - Linkage is by exact name match.
  # - Prefer user-owned lorebooks; fall back to system public lorebooks.
  #
  # Cache stores name -> lorebook_id (or 0 for miss). On cache hit, we double-check
  # accessibility + name match before trusting the cached id.
  class NameResolver
    CACHE_VERSION = 1
    MISS = 0
    DEFAULT_TTL = 6.hours
    DEFAULT_MISS_TTL = 5.minutes

    def initialize(cache: Rails.cache, ttl: DEFAULT_TTL, miss_ttl: DEFAULT_MISS_TTL)
      @cache = cache
      @ttl = ttl
      @miss_ttl = miss_ttl
    end

    # @param user [User, nil]
    # @param name [String, nil]
    # @return [Lorebook, nil]
    def resolve(user:, name:)
      normalized = normalize(name)
      return nil unless normalized

      id = resolve_id(user: user, name: normalized)
      return nil unless id

      Lorebook.accessible_to_system_or_owned(user).find_by(id: id, name: normalized)
    end

    # Delete any cached mapping for this (user, name).
    #
    # Useful when lorebooks are created/renamed and we want soft-link resolution
    # to reflect changes immediately (especially for negative-cache entries).
    #
    # @param user [User, nil]
    # @param name [String, nil]
    # @return [void]
    def invalidate(user:, name:)
      normalized = normalize(name)
      return unless normalized

      @cache.delete(cache_key(user: user, name: normalized))
    end

    # @param user [User, nil]
    # @param name [String]
    # @return [Integer, nil]
    def resolve_id(user:, name:)
      normalized = normalize(name)
      return nil unless normalized

      key = cache_key(user: user, name: normalized)
      cached = @cache.read(key)

      if cached.nil?
        id = compute_id(user: user, name: normalized)
        @cache.write(key, id || MISS, expires_in: id ? @ttl : @miss_ttl)
        return id
      end

      cached_id = cached.to_i
      return nil if cached_id == MISS

      if valid_id?(user: user, id: cached_id, name: normalized)
        return cached_id
      end

      id = compute_id(user: user, name: normalized)
      @cache.write(key, id || MISS, expires_in: id ? @ttl : @miss_ttl)
      id
    end

    private

    def normalize(name)
      value = name.to_s.strip
      value.empty? ? nil : value
    end

    def cache_key(user:, name:)
      user_part = user&.id ? "u#{user.id}" : "system"
      "lorebooks:name_resolver:v#{CACHE_VERSION}:#{user_part}:#{name}"
    end

    def valid_id?(user:, id:, name:)
      Lorebook.accessible_to_system_or_owned(user).where(id: id, name: name).exists?
    end

    def compute_id(user:, name:)
      scope = Lorebook.accessible_to_system_or_owned(user).where(name: name)

      if user&.id
        owned = scope.where(user_id: user.id).order(updated_at: :desc, id: :desc).pick(:id)
        return owned if owned
      end

      scope.where(user_id: nil, visibility: "public").order(updated_at: :desc, id: :desc).pick(:id)
    end
  end
end
