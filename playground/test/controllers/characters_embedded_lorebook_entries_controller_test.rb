# frozen_string_literal: true

require "test_helper"

class Characters::EmbeddedLorebookEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :member

    @user = users(:member)
    @character = characters(:ready_v2)
    @character.update!(user: @user, visibility: "private", locked_at: nil)

    seed_embedded_book!
  end

  test "create adds an embedded entry" do
    before = embedded_entries.size

    post character_embedded_lorebook_entries_url(@character), params: {
      character_book_entry: {
        comment: "Test Entry",
        keys: ["hello"].to_json,
        content: "Hello world",
        enabled: "1",
        insertion_order: "100",
      },
    }

    assert_redirected_to edit_character_url(@character)
    assert_equal before + 1, embedded_entries.size
    assert embedded_entries.any? { |e| e[:content] == "Hello world" }
  end

  test "update edits an embedded entry" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    patch character_embedded_lorebook_entry_url(@character, entry_id), params: {
      character_book_entry: {
        comment: "Updated Title",
        keys: ["dragon"].to_json,
        content: "Updated content",
        enabled: "1",
        insertion_order: "10",
      },
    }

    assert_redirected_to edit_character_url(@character)
    updated = embedded_entries.find { |e| e[:id].to_s == entry_id }
    assert_equal "Updated content", updated[:content]
    assert_equal "Updated Title", updated[:comment]
    assert_equal 10, updated[:insertion_order]
  end

  # REGRESSION TEST: Ensure partial updates (like toggle) don't lose data
  test "partial update (toggle enabled only) preserves all other fields" do
    # Seed entry with rich data
    seed_entry_with_all_fields!
    entry = embedded_entries.find { |e| e[:comment] == "Rich Entry" }
    entry_id = entry[:id].to_s

    # Store original values
    original_keys = entry[:keys]
    original_secondary_keys = entry[:secondary_keys]
    original_content = entry[:content]
    original_comment = entry[:comment]
    original_insertion_order = entry[:insertion_order]
    original_position = entry[:position]
    original_use_regex = entry[:use_regex]

    # Only toggle enabled (simulates inline toggle from UI)
    patch character_embedded_lorebook_entry_url(@character, entry_id), params: {
      character_book_entry: { enabled: "0" },
    }

    assert_redirected_to edit_character_url(@character)

    # Verify NO data was lost
    updated = embedded_entries.find { |e| e[:id].to_s == entry_id }

    assert_equal false, updated[:enabled], "enabled should be toggled to false"
    assert_equal original_keys, updated[:keys], "keys should NOT be lost"
    assert_equal original_secondary_keys, updated[:secondary_keys], "secondary_keys should NOT be lost"
    assert_equal original_content, updated[:content], "content should NOT be lost"
    assert_equal original_comment, updated[:comment], "comment should NOT be lost"
    assert_equal original_insertion_order, updated[:insertion_order], "insertion_order should NOT be lost"
    assert_equal original_position, updated[:position], "position should NOT be lost"
    assert_equal original_use_regex, updated[:use_regex], "use_regex should NOT be lost"
  end

  test "partial update preserves ID" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    patch character_embedded_lorebook_entry_url(@character, entry_id), params: {
      character_book_entry: { enabled: "0" },
    }

    assert_redirected_to edit_character_url(@character)

    # Verify ID was NOT changed
    updated = embedded_entries.find { |e| e[:id].to_s == entry_id }
    assert_not_nil updated, "Entry should still exist with same ID"
    assert_equal entry_id, updated[:id].to_s
  end

  test "destroy removes an embedded entry" do
    entry_id = embedded_entries.first.fetch(:id).to_s
    before = embedded_entries.size

    delete character_embedded_lorebook_entry_url(@character, entry_id)

    assert_redirected_to edit_character_url(@character)
    assert_equal before - 1, embedded_entries.size
  end

  test "destroy with turbo_stream refreshes entries section (count updates)" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    delete character_embedded_lorebook_entry_url(@character, entry_id, inline: 1), as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", response.body

    target = ActionView::RecordIdentifier.dom_id(@character, :embedded_lorebook_entries)
    assert_includes response.body, %(target="#{target}")
  end

  test "destroy without inline redirects back to character edit (for entry edit page UX)" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    delete character_embedded_lorebook_entry_url(@character, entry_id), as: :turbo_stream

    assert_redirected_to edit_character_url(@character)
  end

  test "reorder updates insertion_order for all entries and returns turbo_stream" do
    data = @character.data.to_h.deep_symbolize_keys

    book = data[:character_book].is_a?(Hash) ? data[:character_book] : data[:character_book]&.to_h&.deep_symbolize_keys || {}
    entries = book[:entries] || []

    entries << {
      id: "entry-2",
      keys: ["b"],
      content: "Entry 2",
      enabled: true,
      insertion_order: 200,
    }
    entries << {
      id: "entry-3",
      keys: ["c"],
      content: "Entry 3",
      enabled: true,
      insertion_order: 300,
    }

    book[:entries] = entries
    data[:character_book] = book
    @character.update!(data: data, file_sha256: nil)

    patch reorder_character_embedded_lorebook_entries_url(@character),
          as: :turbo_stream,
          params: { positions: %w[entry-3 entry-1 entry-2] }

    assert_response :success
    assert_match "turbo-stream", response.body

    reordered = embedded_entries
    assert_equal %w[entry-3 entry-1 entry-2], reordered.map { |e| e[:id] }
    assert_equal [0, 10, 20], reordered.map { |e| e[:insertion_order] }
  end

  test "non-owner cannot create" do
    sign_in :admin

    post character_embedded_lorebook_entries_url(@character), params: {
      character_book_entry: {
        comment: "Hacked Entry",
        keys: ["hack"].to_json,
        content: "Hacked content",
      },
    }

    assert_response :not_found
  end

  private

  def seed_embedded_book!
    data = @character.data.to_h.deep_symbolize_keys
    data[:character_book] = {
      entries: [
        {
          id: "entry-1",
          keys: ["dragon"],
          content: "Dragons are real.",
          enabled: true,
          insertion_order: 100,
          use_regex: false,
        },
      ],
    }
    @character.update!(data: data, file_sha256: nil)
  end

  # Seed an entry with ALL fields populated - for regression testing
  def seed_entry_with_all_fields!
    data = @character.data.to_h.deep_symbolize_keys
    book = data[:character_book].is_a?(Hash) ? data[:character_book] : data[:character_book]&.to_h&.deep_symbolize_keys || {}
    entries = book[:entries] || []

    entries << {
      id: "rich-entry-1",
      comment: "Rich Entry",
      keys: %w[magic power ability],
      secondary_keys: %w[spell cast],
      content: "This is detailed content about magic and power.",
      enabled: true,
      constant: false,
      use_regex: true,
      position: "before_char",
      insertion_order: 200,
      depth: 4,
      selective: true,
      selective_logic: "AND",
      probability: 100,
      use_probability: true,
      group: "magic_group",
      group_weight: 50,
      sticky: 3,
      cooldown: 2,
    }

    book[:entries] = entries
    data[:character_book] = book
    @character.update!(data: data, file_sha256: nil)
  end

  def embedded_entries
    char = Character.find(@character.id)
    book = char.data&.character_book
    return [] unless book

    entries = book.respond_to?(:entries) ? book.entries : book[:entries]
    Array(entries).map do |entry|
      entry.is_a?(Hash) ? entry.deep_symbolize_keys : entry.to_h.deep_symbolize_keys
    end
  end
end
