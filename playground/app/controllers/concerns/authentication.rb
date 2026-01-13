# frozen_string_literal: true

# Authentication concern for controllers.
#
# Provides session-based authentication using secure tokens stored in cookies.
# Follows the Campfire pattern for authentication.
#
# @example Allow unauthenticated access
#   class PublicController < ApplicationController
#     allow_unauthenticated_access
#   end
#
# @example Require unauthenticated access (for login pages)
#   class SessionsController < ApplicationController
#     require_unauthenticated_access only: %i[new create]
#   end
#
module Authentication
  extend ActiveSupport::Concern
  include Authentication::SessionLookup

  included do
    before_action :require_authentication
    helper_method :signed_in?
  end

  class_methods do
    # Skip authentication for specified actions.
    #
    # @param options [Hash] options passed to skip_before_action
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end

    # Require that user is NOT signed in for specified actions.
    # Redirects signed-in users to root.
    #
    # @param options [Hash] options passed to before_action
    def require_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      before_action :restore_authentication, :redirect_signed_in_user_to_root, **options
    end
  end

  private

  # Check if user is currently signed in.
  #
  # @return [Boolean] true if signed in
  def signed_in?
    Current.user.present?
  end

  def require_administrator
    (signed_in? && Current.user.administrator?) || redirect_to(root_url)
  end

  # Require authentication, redirecting to login if not authenticated.
  def require_authentication
    restore_authentication || request_authentication
  end

  # Restore authentication from session cookie.
  #
  # @return [Boolean] true if authentication was restored
  def restore_authentication
    if (session = find_session_by_cookie)
      resume_session(session)
    end
  end

  # Redirect to login page, storing return URL.
  def request_authentication
    session[:return_to_after_authenticating] = request.url
    redirect_to new_session_url
  end

  # Redirect signed-in users away from auth pages.
  def redirect_signed_in_user_to_root
    redirect_to root_url if signed_in?
  end

  # Start a new session for a user.
  #
  # @param user [User] the user to start session for
  # @return [Session] the created session
  def start_new_session_for(user)
    user.sessions.start!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
      authenticated_as(session)
    end
  end

  # Resume an existing session.
  #
  # @param session [Session] the session to resume
  def resume_session(session)
    session.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
    authenticated_as(session)
  end

  # Set the current user and session cookie.
  #
  # @param session [Session] the authenticated session
  def authenticated_as(session)
    Current.user = session.user
    cookies.signed.permanent[:session_token] = {
      value: session.token,
      httponly: true,
      same_site: :lax,
      secure: Rails.env.production?,
    }
  end

  # Get the URL to redirect to after authentication.
  #
  # @return [String] the return URL or root
  def post_authenticating_url
    session.delete(:return_to_after_authenticating) || root_url
  end

  # Clear the session cookie.
  def reset_authentication
    cookies.delete(:session_token)
  end
end
