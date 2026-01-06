# frozen_string_literal: true

class FixProviderForeignKeys < ActiveRecord::Migration[8.0]
  def change
    # Remove existing foreign keys
    remove_foreign_key :presets, :llm_providers
    remove_foreign_key :space_memberships, :llm_providers

    # Add back with on_delete: :nullify
    # When a provider is deleted, just set the reference to NULL
    add_foreign_key :presets, :llm_providers, on_delete: :nullify
    add_foreign_key :space_memberships, :llm_providers, on_delete: :nullify
  end
end
