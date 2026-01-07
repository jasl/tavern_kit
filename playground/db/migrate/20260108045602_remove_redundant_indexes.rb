# frozen_string_literal: true

class RemoveRedundantIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :character_assets, name: "index_character_assets_on_character_id" if index_exists?(:character_assets, :character_id, name: "index_character_assets_on_character_id")
    remove_index :character_lorebooks, name: "index_character_lorebooks_on_character_id" if index_exists?(:character_lorebooks, :character_id, name: "index_character_lorebooks_on_character_id")
    remove_index :conversation_runs, name: "index_conversation_runs_on_conversation_id" if index_exists?(:conversation_runs, :conversation_id, name: "index_conversation_runs_on_conversation_id")
    remove_index :message_swipes, name: "index_message_swipes_on_message_id" if index_exists?(:message_swipes, :message_id, name: "index_message_swipes_on_message_id")
    remove_index :messages, name: "index_messages_on_conversation_id" if index_exists?(:messages, :conversation_id, name: "index_messages_on_conversation_id")
    remove_index :presets, name: "index_presets_on_user_id" if index_exists?(:presets, :user_id, name: "index_presets_on_user_id")
    remove_index :space_lorebooks, name: "index_space_lorebooks_on_space_id" if index_exists?(:space_lorebooks, :space_id, name: "index_space_lorebooks_on_space_id")
  end
end
