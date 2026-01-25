# frozen_string_literal: true

class MakeTranslationRunsMessageOptional < ActiveRecord::Migration[8.2]
  def change
    change_column_null :translation_runs, :message_id, true
  end
end
