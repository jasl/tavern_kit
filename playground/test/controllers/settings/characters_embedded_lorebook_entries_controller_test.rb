# frozen_string_literal: true

require "test_helper"

class Settings::Characters::EmbeddedLorebookEntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin

    @character = characters(:ready_v2)
    @character.update!(locked_at: nil, file_sha256: nil)
    seed_embedded_book!
  end

  test "create adds an embedded entry" do
    before = embedded_entries.size

    post settings_character_embedded_lorebook_entries_url(@character), params: {
      character_book_entry: {
        comment: "Admin Entry",
        keys: ["admin"].to_json,
        content: "Admin content",
        enabled: "1",
      },
    }

    assert_redirected_to edit_settings_character_url(@character)
    assert_equal before + 1, embedded_entries.size
  end

  test "update edits an embedded entry" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    patch settings_character_embedded_lorebook_entry_url(@character, entry_id), params: {
      character_book_entry: {
        keys: ["dragon"].to_json,
        content: "Updated by admin",
        enabled: "1",
      },
    }

    assert_redirected_to edit_settings_character_url(@character)
    updated = embedded_entries.find { |e| e[:id].to_s == entry_id }
    assert_equal "Updated by admin", updated[:content]
  end

  # REGRESSION TEST: Ensure partial updates (like toggle) don't lose data
  test "partial update (toggle enabled only) preserves all other fields" do
    seed_entry_with_all_fields!
    entry = embedded_entries.find { |e| e[:comment] == "Rich Entry" }
    entry_id = entry[:id].to_s

    # Store original values
    original_keys = entry[:keys]
    original_secondary_keys = entry[:secondary_keys]
    original_content = entry[:content]
    original_comment = entry[:comment]

    # Only toggle enabled (simulates inline toggle from UI)
    patch settings_character_embedded_lorebook_entry_url(@character, entry_id), params: {
      character_book_entry: { enabled: "0" },
    }

    assert_redirected_to edit_settings_character_url(@character)

    # Verify NO data was lost
    updated = embedded_entries.find { |e| e[:id].to_s == entry_id }

    assert_equal false, updated[:enabled], "enabled should be toggled to false"
    assert_equal original_keys, updated[:keys], "keys should NOT be lost"
    assert_equal original_secondary_keys, updated[:secondary_keys], "secondary_keys should NOT be lost"
    assert_equal original_content, updated[:content], "content should NOT be lost"
    assert_equal original_comment, updated[:comment], "comment should NOT be lost"
  end

  test "partial update preserves ID" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    patch settings_character_embedded_lorebook_entry_url(@character, entry_id), params: {
      character_book_entry: { enabled: "0" },
    }

    assert_redirected_to edit_settings_character_url(@character)

    updated = embedded_entries.find { |e| e[:id].to_s == entry_id }
    assert_not_nil updated, "Entry should still exist with same ID"
    assert_equal entry_id, updated[:id].to_s
  end

  test "destroy removes an embedded entry" do
    entry_id = embedded_entries.first.fetch(:id).to_s
    before = embedded_entries.size

    delete settings_character_embedded_lorebook_entry_url(@character, entry_id)

    assert_redirected_to edit_settings_character_url(@character)
    assert_equal before - 1, embedded_entries.size
  end

  test "destroy with turbo_stream refreshes entries section (count updates)" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    delete settings_character_embedded_lorebook_entry_url(@character, entry_id, inline: 1), as: :turbo_stream

    assert_response :success
    assert_match "turbo-stream", response.body

    target = ActionView::RecordIdentifier.dom_id(@character, :embedded_lorebook_entries)
    assert_includes response.body, %(target="#{target}")
  end

  test "destroy without inline redirects back to character edit (for entry edit page UX)" do
    entry_id = embedded_entries.first.fetch(:id).to_s

    delete settings_character_embedded_lorebook_entry_url(@character, entry_id), as: :turbo_stream

    assert_redirected_to edit_settings_character_url(@character)
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

    patch reorder_settings_character_embedded_lorebook_entries_url(@character),
          as: :turbo_stream,
          params: { positions: %w[entry-3 entry-1 entry-2] }

    assert_response :success
    assert_match "turbo-stream", response.body

    reordered = embedded_entries
    assert_equal %w[entry-3 entry-1 entry-2], reordered.map { |e| e[:id] }
    assert_equal [0, 10, 20], reordered.map { |e| e[:insertion_order] }
  end

  test "locked character prevents modification" do
    @character.update_column(:locked_at, Time.current)

    post settings_character_embedded_lorebook_entries_url(@character), params: {
      character_book_entry: {
        comment: "Should fail",
        keys: ["test"].to_json,
        content: "Test content",
      },
    }

    # Locked characters redirect with error
    assert_redirected_to edit_settings_character_url(@character)
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
