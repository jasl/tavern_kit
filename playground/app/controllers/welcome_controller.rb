# frozen_string_literal: true

class WelcomeController < ApplicationController
  def index
    # Featured characters for the hero section
    scope = Character.accessible_to(Current.user).ready
    @ready_characters_count = scope.count
    @featured_characters = scope.ordered.with_attached_portrait.limit(6)

    # Recent conversations (latest 3, sorted by recent activity)
    @recent_conversations = Conversation.root
                                        .joins(:space)
                                        .where(spaces: { type: "Spaces::Playground" })
                                        .merge(Space.accessible_to(Current.user))
                                        .merge(Space.active)
                                        .with_last_message_preview
                                        .by_recent_activity
                                        .includes(space: { characters: { portrait_attachment: :blob } })
                                        .limit(3)
  end
end
