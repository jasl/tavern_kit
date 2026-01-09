# frozen_string_literal: true

namespace :counters do
  desc "Reset all counter cache columns"
  task reset: :environment do
    puts "Resetting counter caches..."

    # Reset User counters
    puts "  Resetting User.characters_count..."
    User.find_each do |user|
      count = Character.where(user_id: user.id).count
      User.where(id: user.id).update_all(characters_count: count)
    end

    puts "  Resetting User.lorebooks_count..."
    User.find_each do |user|
      count = Lorebook.where(user_id: user.id).count
      User.where(id: user.id).update_all(lorebooks_count: count)
    end

    puts "  Resetting User.conversations_count..."
    User.find_each do |user|
      # Count root conversations owned by this user (via Space.owner_id)
      count = Conversation.root.joins(:space).where(spaces: { owner_id: user.id }).count
      User.where(id: user.id).update_all(conversations_count: count)
    end

    puts "  Resetting User.messages_count..."
    User.find_each do |user|
      # Count messages from SpaceMemberships where user_id matches
      count = Message.joins(:space_membership).where(space_memberships: { user_id: user.id }).count
      User.where(id: user.id).update_all(messages_count: count)
    end

    # Reset Character counters
    puts "  Resetting Character.messages_count..."
    Character.find_each do |character|
      # Count messages from SpaceMemberships where character_id matches
      count = Message.joins(:space_membership).where(space_memberships: { character_id: character.id }).count
      Character.where(id: character.id).update_all(messages_count: count)
    end

    puts "Done!"
  end

  desc "Show current counter values for all users"
  task show: :environment do
    puts "User counter values:"
    User.find_each do |user|
      actual_chars = Character.where(user_id: user.id).count
      actual_lore = Lorebook.where(user_id: user.id).count
      actual_convs = Conversation.root.joins(:space).where(spaces: { owner_id: user.id }).count
      actual_msgs = Message.joins(:space_membership).where(space_memberships: { user_id: user.id }).count

      puts "  #{user.name} (#{user.id}):"
      puts "    characters_count: #{user.characters_count} (actual: #{actual_chars})"
      puts "    lorebooks_count: #{user.lorebooks_count} (actual: #{actual_lore})"
      puts "    conversations_count: #{user.conversations_count} (actual: #{actual_convs})"
      puts "    messages_count: #{user.messages_count} (actual: #{actual_msgs})"
    end

    puts "\nCharacter counter values (first 10):"
    Character.limit(10).find_each do |char|
      actual_msgs = Message.joins(:space_membership).where(space_memberships: { character_id: char.id }).count
      puts "  #{char.name} (#{char.id}): messages_count: #{char.messages_count} (actual: #{actual_msgs})"
    end
  end
end
