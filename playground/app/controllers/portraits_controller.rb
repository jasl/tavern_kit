# frozen_string_literal: true

# Serves portrait images via signed IDs for secure, relative URL access.
#
# Following Campfire's pattern: instead of using Active Storage's absolute URLs
# (which require host/port configuration), we serve portraits through a custom
# controller using relative paths that work from any host.
#
# @example Usage in views
#   image_tag fresh_space_membership_portrait_path(membership)
#
class PortraitsController < ApplicationController
  skip_before_action :require_authentication

  # Prevent browsers from caching redirects to ensure fresh portraits
  before_action :set_no_cache_headers

  rescue_from(ActiveSupport::MessageVerifier::InvalidSignature) { serve_default_portrait }
  rescue_from(ActiveRecord::RecordNotFound) { serve_default_portrait }

  # GET /portraits/space_memberships/:signed_id
  # Serves a space membership's portrait (character portrait when present).
  def space_membership
    membership = SpaceMembership.find_signed!(params[:signed_id], purpose: :portrait)

    if membership.character&.portrait&.attached?
      redirect_to_portrait(membership.character.portrait)
    else
      serve_default_portrait
    end
  end

  # GET /portraits/characters/:signed_id
  # Serves a character's portrait.
  def character
    character = Character.find_signed!(params[:signed_id], purpose: :portrait)

    if character.portrait.attached?
      redirect_to_portrait(character.portrait)
    else
      serve_default_portrait
    end
  end

  private

  VARIANT_OPTIONS = { resize_to_limit: [400, 600], format: :webp }.freeze

  def redirect_to_portrait(attachment)
    # Use rails_representation_path for relative URL
    redirect_to rails_representation_path(
      attachment.variant(VARIANT_OPTIONS),
      only_path: true
    ), allow_other_host: false
  end

  def serve_default_portrait
    send_file Rails.root.join("app/assets/images/default_portrait.png"),
              content_type: "image/png",
              disposition: :inline
  end

  def set_no_cache_headers
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end
end
