# frozen_string_literal: true

class WelcomeController < ApplicationController
  def index
    scope = Character.accessible_to(Current.user).ready
    @ready_characters_count = scope.count
    @featured_characters = scope.ordered.limit(6)
  end
end
