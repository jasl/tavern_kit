# frozen_string_literal: true

# Seed LLM providers
puts "Seeding LLM providers..."
LLMProvider.seed_presets!
puts "  Created #{LLMProvider.count} providers"

# Print the effective default provider (if any)
default_provider = LLMProvider.get_default
puts "  Default provider is '#{default_provider.name}'" if default_provider

# Seed presets
puts "Seeding presets..."
Preset.seed_system_presets!
puts "  Created #{Preset.system_presets.count} system presets"

# Print the effective default preset (if any)
default_preset = Preset.get_default
puts "  Default preset is '#{default_preset.name}'" if default_preset

# Seed debug settings (for playground development)
puts "Seeding debug settings..."
Setting.set("conversation.snapshot_prompt", "true")
puts "  Set conversation.snapshot_prompt = true"

puts "Done!"
