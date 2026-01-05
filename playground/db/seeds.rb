# frozen_string_literal: true

# Seed LLM providers
puts "Seeding LLM providers..."
LLMProvider.seed_presets!
puts "  Created #{LLMProvider.count} providers"

# Update supports_logprobs for existing providers based on preset values
puts "Updating supports_logprobs values..."
LLMProvider::PRESETS.each do |_key, config|
  provider = LLMProvider.find_by(name: config[:name])
  next unless provider

  provider.update!(supports_logprobs: config[:supports_logprobs] || false)
end
puts "  Updated supports_logprobs for existing providers"

# Ensure a default provider is set
default_provider = LLMProvider.get_default
puts "  Set default provider to '#{default_provider.name}'" if default_provider

# Seed debug settings (for playground development)
puts "Seeding debug settings..."
Setting.set("conversation.snapshot_prompt", "true")
puts "  Set conversation.snapshot_prompt = true"

puts "Done!"
