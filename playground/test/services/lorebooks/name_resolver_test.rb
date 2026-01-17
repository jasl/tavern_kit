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
end
