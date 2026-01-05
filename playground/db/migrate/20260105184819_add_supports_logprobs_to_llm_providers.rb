class AddSupportsLogprobsToLLMProviders < ActiveRecord::Migration[8.1]
  def change
    add_column :llm_providers, :supports_logprobs, :boolean, default: false, null: false
  end
end
