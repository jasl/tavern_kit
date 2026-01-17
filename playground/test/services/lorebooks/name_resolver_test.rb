# frozen_string_literal: true

require "test_helper"

class Lorebooks::NameResolverTest < ActiveSupport::TestCase
  test "prefers owned lorebook over system public when names collide" do
    user = users(:member)

    system = Lorebook.create!(name: "Eldoria", visibility: "public", user: nil)
    owned = Lorebook.create!(name: "Eldoria", visibility: "private", user: user)

    resolver = Lorebooks::NameResolver.new(cache: ActiveSupport::Cache::NullStore.new)
    resolved = resolver.resolve(user: user, name: "Eldoria")

    assert_equal owned.id, resolved&.id
    refute_equal system.id, resolved&.id
  end

  test "picks most recently updated owned lorebook when duplicate owned names exist" do
    user = users(:member)

    older = Lorebook.create!(name: "Eldoria", visibility: "private", user: user)
    newer = Lorebook.create!(name: "Eldoria", visibility: "private", user: user)

    # Make the older record appear more recently updated.
    older.update_column(:updated_at, 1.day.from_now)

    resolver = Lorebooks::NameResolver.new(cache: ActiveSupport::Cache::NullStore.new)
    resolved = resolver.resolve(user: user, name: "Eldoria")

    assert_equal older.id, resolved&.id
    refute_equal newer.id, resolved&.id
  end

  test "when user is nil, only system public lorebooks are eligible" do
    user = users(:member)

    system_public = Lorebook.create!(name: "Eldoria", visibility: "public", user: nil)
    Lorebook.create!(name: "Eldoria", visibility: "private", user: user)

    resolver = Lorebooks::NameResolver.new(cache: ActiveSupport::Cache::NullStore.new)
    resolved = resolver.resolve(user: nil, name: "Eldoria")

    assert_equal system_public.id, resolved&.id
  end

  test "normalizes input by stripping whitespace but keeps exact (case-sensitive) matching" do
    user = users(:member)
    lorebook = Lorebook.create!(name: "Eldoria", visibility: "private", user: user)

    resolver = Lorebooks::NameResolver.new(cache: ActiveSupport::Cache::NullStore.new)

    assert_equal lorebook.id, resolver.resolve(user: user, name: "  Eldoria  ")&.id
    assert_nil resolver.resolve(user: user, name: "eldoria")
  end

  test "uses cache to avoid extra lookup work on repeated resolves" do
    user = users(:member)
    store = ActiveSupport::Cache::MemoryStore.new
    resolver = Lorebooks::NameResolver.new(cache: store, ttl: 1.day, miss_ttl: 1.day)

    lorebook = Lorebook.create!(name: "Eldoria", visibility: "private", user: user)

    # Warm the cache (miss -> compute_id + fetch record).
    assert_equal lorebook.id, resolver.resolve(user: user, name: "Eldoria")&.id

    resolved = nil
    query_count = 0
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:name] == "SCHEMA"
      next if payload[:name] == "TRANSACTION"
      next if payload[:cached]

      query_count += 1
    end

    ActiveRecord::Base.uncached do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        resolved = resolver.resolve(user: user, name: "Eldoria")
      end
    end

    assert_equal lorebook.id, resolved&.id
    assert_equal 1, query_count
  end
end

class Lorebooks::NameResolverCacheInvalidationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "invalidates negative cache on create so new lorebook resolves immediately" do
    user = users(:member)
    store = ActiveSupport::Cache::MemoryStore.new

    Rails.stubs(:cache).returns(store)
    resolver = Lorebooks::NameResolver.new(cache: store, ttl: 1.day, miss_ttl: 1.day)

    assert_nil resolver.resolve(user: user, name: "Eldoria")

    lorebook = Lorebook.create!(name: "Eldoria", visibility: "private", user: user)
    assert_equal lorebook.id, resolver.resolve(user: user, name: "Eldoria")&.id

    lorebook.destroy!
  end

  test "invalidates negative cache on rename so new name resolves immediately" do
    user = users(:member)
    store = ActiveSupport::Cache::MemoryStore.new

    Rails.stubs(:cache).returns(store)
    resolver = Lorebooks::NameResolver.new(cache: store, ttl: 1.day, miss_ttl: 1.day)

    lorebook = Lorebook.create!(name: "Alpha", visibility: "private", user: user)
    assert_nil resolver.resolve(user: user, name: "Beta")

    lorebook.update!(name: "Beta")
    assert_equal lorebook.id, resolver.resolve(user: user, name: "Beta")&.id

    lorebook.destroy!
  end
end
