# frozen_string_literal: true

# =============================================================================
# Playground Seeds - Development & Demo Data
# =============================================================================
#
# This file seeds the database with:
# 1. LLM providers (required for API connections)
# 2. System presets (required for prompt building)
# 3. Demo user account (optional, for development)
# 4. Example characters (optional, for testing)
# 5. Debug settings (optional, for development)
#
# Usage:
#   rails db:seed                    # Seed everything
#   SKIP_DEMO_DATA=1 rails db:seed  # Skip demo user/characters
#
# =============================================================================

skip_demo = ENV["SKIP_DEMO_DATA"] == "1"

# -----------------------------------------------------------------------------
# 1. Seed LLM Providers (Required)
# -----------------------------------------------------------------------------
puts "Seeding LLM providers..."
LLMProvider.seed_presets!
puts "  ✓ Created #{LLMProvider.count} providers"

default_provider = LLMProvider.get_default
if default_provider
  puts "  ✓ Default provider: #{default_provider.name}"
else
  puts "  ⚠ No default provider set. Configure one in Settings."
end

# -----------------------------------------------------------------------------
# 2. Seed System Presets (Required)
# -----------------------------------------------------------------------------
puts "\nSeeding presets..."
Preset.seed_system_presets!
puts "  ✓ Created #{Preset.system_presets.count} system presets"

default_preset = Preset.get_default
if default_preset
  puts "  ✓ Default preset: #{default_preset.name}"
else
  puts "  ⚠ No default preset set. Configure one in Settings."
end

# -----------------------------------------------------------------------------
# 3. Seed Demo User (Optional, Development Only)
# -----------------------------------------------------------------------------
unless skip_demo
  puts "\nSeeding demo user..."
  demo_user = User.find_or_create_by!(email: "demo@example.com") do |user|
    user.name = "Demo Admin"
    user.password = "password"
    user.role = "administrator"
  end
  puts "  ✓ Demo user: #{demo_user.email} (password: password)"
  puts "    Administrator: #{demo_user.administrator? ? 'Yes' : 'No'}"
end

# -----------------------------------------------------------------------------
# 4. Seed Example Characters (Optional, Development Only)
# -----------------------------------------------------------------------------
unless skip_demo
  puts "\nSeeding example characters..."

  # Create a simple example character (inspired by fixtures but re-interpreted)
  # This is a friendly AI assistant character card in CCv2 format
  example_character = Character.find_or_create_by!(name: "Alice") do |char|
    char.data = {
      name: "Alice",
      description: "A friendly AI assistant who loves helping people learn and explore new ideas. She's patient, curious, and always eager to have meaningful conversations.",
      personality: "Helpful, curious, patient, and enthusiastic about learning",
      scenario: "You are chatting with Alice, a knowledgeable AI assistant who enjoys having conversations about various topics.",
      first_mes: "Hi! I'm Alice. How can I help you today?",
      mes_example: "<START>\n{{user}}: What's your favorite hobby?\n{{char}}: I love learning new things! Every conversation teaches me something interesting. What about you?\n<START>\n{{user}}: Do you ever get tired?\n{{char}}: Not really! I find every conversation energizing in its own way.",
      tags: ["friendly", "assistant", "sfw"],
    }
    char.spec_version = 2
    char.status = "ready"
    char.visibility = "private"
  end
  puts "  ✓ Character: #{example_character.name}"
end

# -----------------------------------------------------------------------------
# 5. Seed Debug Settings (Optional, Development Only)
# -----------------------------------------------------------------------------
unless skip_demo
  puts "\nSeeding debug settings..."
  Setting.set("conversation.snapshot_prompt", "true")
  puts "  ✓ conversation.snapshot_prompt = true"
end

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
puts "\n" + ("=" * 80)
puts "Seeding complete!"
puts ("=" * 80)
puts "✓ LLM Providers: #{LLMProvider.count}"
puts "✓ Presets: #{Preset.count}"
unless skip_demo
  puts "✓ Users: #{User.count}"
  puts "✓ Characters: #{Character.count}"

  puts ""
  puts "Demo user: #{demo_user.email}"
  puts "Demo user password: password"
end
puts "\nNext steps:"
if default_provider.nil?
  puts "  1. Configure a default LLM provider in Settings"
else
  puts "  1. (Optional) Configure LLM API keys for #{default_provider.name}"
end
unless skip_demo
  puts "  2. Sign in with demo@example.com / password"
  puts "  3. Create a Space and start chatting!"
else
  puts "  2. Create a user account"
  puts "  3. Create characters and spaces"
end
puts ("=" * 80)
