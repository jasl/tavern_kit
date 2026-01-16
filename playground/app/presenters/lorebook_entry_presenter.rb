# frozen_string_literal: true

# Presenter for displaying lorebook entries in views.
#
# Why: in this app, a "lorebook entry" can come from different sources:
# - Embedded character_book entries (JSON) → Hash
# - Linked lorebook entries (database)     → LorebookEntry (ActiveRecord)
# - (Optionally) schema objects            → TavernKit::Character::CharacterBookEntrySchema
#
# This presenter normalizes all of them into a consistent interface for ERB.
class LorebookEntryPresenter
  def initialize(entry)
    @entry = entry
  end

  def enabled?
    value = fetch(:enabled)
    value.nil? ? true : value == true
  end

  def constant?
    return @entry.constant? if @entry.respond_to?(:constant?)

    fetch(:constant) == true
  end

  def use_regex?
    return @entry.regex? if @entry.respond_to?(:regex?)
    return @entry.use_regex? if @entry.respond_to?(:use_regex?)

    fetch(:use_regex) == true
  end

  def position
    fetch(:position)&.to_s
  end

  def keys
    Array(fetch(:keys)).map(&:to_s)
  end

  def secondary_keys
    Array(fetch(:secondary_keys)).map(&:to_s)
  end

  def selective?
    if @entry.respond_to?(:selective?)
      @entry.selective?
    else
      fetch(:selective) == true && secondary_keys.any?
    end
  end

  def name
    if @entry.respond_to?(:display_name)
      @entry.display_name.to_s
    else
      (fetch(:comment).presence || fetch(:name).presence || keys.first(3).join(", ").presence || "Entry").to_s
    end
  end

  def content
    fetch(:content).to_s
  end

  private

  def fetch(key)
    if @entry.is_a?(Hash)
      @entry[key] || @entry[key.to_s]
    elsif @entry.respond_to?(key)
      @entry.public_send(key)
    end
  end
end
