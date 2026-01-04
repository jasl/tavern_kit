# frozen_string_literal: true

# Service object for first-run setup.
#
# Creates the initial Account and administrator User when the
# application is first launched.
#
# @example Complete first run setup
#   user = FirstRun.create!(name: "Admin", email: "admin@example.com",
#                           password: "secret")
#
class FirstRun
  # Create the initial account and administrator user.
  #
  # @param user_params [Hash] parameters for the administrator user
  # @option user_params [String] :name user's display name
  # @option user_params [String] :email user's email
  # @option user_params [String] :password user's password
  # @return [User] the created administrator
  def self.create!(user_params)
    ApplicationRecord.transaction do
      user = User.create!(user_params.merge(role: "administrator"))
      Setting.set("site.initialized", true)
      user
    end
  end
end
