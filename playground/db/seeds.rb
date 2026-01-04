# frozen_string_literal: true

# Seed LLM providers
puts "Seeding LLM providers..."
LLMProvider.seed_presets!
puts "  Created #{LLMProvider.count} providers"

# Ensure a default provider is set
default_provider = LLMProvider.get_default
puts "  Set default provider to '#{default_provider.name}'" if default_provider

# Seed debug settings (for playground development)
puts "Seeding debug settings..."
Setting.set("conversation.snapshot_prompt", "true")
puts "  Set conversation.snapshot_prompt = true"

puts "Done!"
