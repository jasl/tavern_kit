# frozen_string_literal: true

# Public character controller for viewing characters.
# Management (create, update, destroy) is handled in Settings::CharactersController.
class CharactersController < ApplicationController
  before_action :set_character, except: %i[index]

  # GET /characters
  # List all ready characters with optional filtering.
  def index
    @characters = Character.accessible_to(Current.user).ready
                           .order(created_at: :desc)
                           .includes(portrait_attachment: :blob)

    # Optional tag filtering
    @characters = @characters.with_tag(params[:tag]) if params[:tag].present?

    # Optional spec version filtering
    @characters = @characters.by_spec_version(params[:version].to_i) if params[:version].present?
  end

  # GET /characters/:id
  # Show character details (read-only).
  def show
  end

  # GET /characters/:id/portrait
  # Redirect to the signed portrait URL for consistent caching.
  def portrait
    redirect_to fresh_character_portrait_path(@character)
  end

  private

  def set_character
    @character = Character.accessible_to(Current.user).ready.find(params[:id])
  end
end
