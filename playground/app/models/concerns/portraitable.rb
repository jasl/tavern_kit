# frozen_string_literal: true

# Provides portrait token generation for models with portraits.
#
# Following Campfire's pattern of using signed IDs for secure,
# relative URL-based portrait serving.
#
# @example Include in a model
#   class Participant < ApplicationRecord
#     include Portraitable
#   end
#
#   participant.portrait_token # => signed ID for portrait URL
#
module Portraitable
  extend ActiveSupport::Concern

  class_methods do
    # Find a record by its portrait token.
    #
    # @param signed_id [String] the signed ID from portrait_token
    # @return [ApplicationRecord] the found record
    # @raise [ActiveSupport::MessageVerifier::InvalidSignature] if invalid
    def from_portrait_token(signed_id)
      find_signed!(signed_id, purpose: :portrait)
    end
  end

  # Generate a signed ID for portrait URL generation.
  #
  # @return [String] signed ID that can be used in portrait URLs
  def portrait_token
    signed_id(purpose: :portrait)
  end
end
