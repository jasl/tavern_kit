# frozen_string_literal: true

# Helper methods for rendering avatars and character portraits.
#
# Provides consistent avatar rendering across the application with
# support for character portraits (400x600, 2:3 aspect ratio), user avatars,
# and space_membership-based delegation.
#
# Following Campfire's pattern: uses relative URLs via custom portrait
# controller instead of Active Storage's absolute URLs. This means avatars
# work correctly regardless of host/port configuration.
#
# Default portrait: app/assets/images/default_portrait.png (400x600)
module PortraitHelper
  # Default portrait image path
  DEFAULT_PORTRAIT = "default_portrait.png"

  # Standard sizes for circular avatars
  AVATAR_SIZES = {
    xs: "w-6 h-6",
    sm: "w-8 h-8",
    md: "w-10 h-10",
    lg: "w-12 h-12",
    xl: "w-16 h-16",
  }.freeze

  # Portrait sizes (2:3 aspect ratio, matching 400x600 standard)
  PORTRAIT_SIZES = {
    xs: "w-12 h-18",
    sm: "w-16 h-24",
    md: "w-20 h-30",
    standard: "w-[200px] h-[300px]",
    lg: "w-32 h-48",
  }.freeze

  # Render a character portrait image.
  #
  # @param character [Character] the character to display
  # @param size [Symbol] portrait size (:xs, :sm, :md, :standard, :lg)
  # @param css_class [String] additional CSS classes
  # @return [String] HTML for the portrait
  def character_portrait(character, size: :md, css_class: "")
    size_class = PORTRAIT_SIZES[size] || PORTRAIT_SIZES[:md]

    content_tag :figure, class: "#{size_class} relative overflow-hidden rounded-lg bg-base-200 shrink-0 #{css_class}" do
      image_tag fresh_character_portrait_path(character),
                class: "w-full h-full object-cover",
                alt: character.name,
                loading: "lazy"
    end
  end

  # Render a user portrait image (2:3 aspect ratio, same as character).
  #
  # @param user [User] the user to display
  # @param size [Symbol] portrait size (:xs, :sm, :md, :standard, :lg)
  # @param css_class [String] additional CSS classes
  # @return [String] HTML for the portrait
  def user_portrait(user, size: :md, css_class: "")
    size_class = PORTRAIT_SIZES[size] || PORTRAIT_SIZES[:md]

    content_tag :figure, class: "#{size_class} relative overflow-hidden rounded-lg bg-base-200 shrink-0 #{css_class}" do
      if user.respond_to?(:portrait) && user.portrait.attached?
        image_tag user.portrait.variant(:standard),
                  class: "w-full h-full object-cover",
                  alt: user.name,
                  loading: "lazy"
      else
        image_tag DEFAULT_PORTRAIT,
                  class: "w-full h-full object-cover",
                  alt: user.name,
                  loading: "lazy"
      end
    end
  end

  # Render a circular user avatar (for small displays like chat bubbles).
  #
  # @param user [User] the user to display
  # @param size [Symbol] avatar size (:xs, :sm, :md, :lg, :xl)
  # @param css_class [String] additional CSS classes
  # @return [String] HTML for the avatar
  def user_avatar(user, size: :md, css_class: "")
    size_class = AVATAR_SIZES[size] || AVATAR_SIZES[:md]

    content_tag :div, class: "avatar #{css_class}" do
      content_tag :div, class: "#{size_class} rounded-full overflow-hidden bg-base-200" do
        if user.respond_to?(:portrait) && user.portrait.attached?
          image_tag user.portrait.variant(:standard),
                    class: "w-full h-full object-cover",
                    alt: user.name
        else
          image_tag DEFAULT_PORTRAIT,
                    class: "w-full h-full object-cover",
                    alt: user.name
        end
      end
    end
  end

  # Render avatar for a space membership (delegates to character or user).
  #
  # @param participant [SpaceMembership] the membership to display
  # @param size [Symbol] size for the avatar/portrait
  # @param css_class [String] additional CSS classes
  # @return [String] HTML for the avatar
  def participant_avatar(participant, size: :md, css_class: "")
    if participant.character.present?
      character_portrait(participant.character, size: size, css_class: css_class)
    elsif participant.user.present?
      user_portrait(participant.user, size: size, css_class: css_class)
    else
      placeholder_portrait(size: size, css_class: css_class)
    end
  end

  # Render a small circular avatar for chat bubbles (legacy DaisyUI chat component).
  # Uses relative URL via space_membership_portrait_path with cache-busting.
  #
  # @param participant [SpaceMembership] the membership to display
  # @param size [Symbol] avatar size
  # @return [String] HTML for the chat avatar
  def chat_avatar(participant, size: :md)
    size_class = AVATAR_SIZES[size] || AVATAR_SIZES[:md]

    content_tag :div, class: "chat-image avatar" do
      content_tag :div, class: "#{size_class} rounded-full overflow-hidden bg-base-200" do
        image_tag space_membership_portrait_url(participant),
                  class: "w-full h-full object-cover",
                  alt: participant.display_name
      end
    end
  end

  # Render a circular avatar for SillyTavern-style messages.
  # Uses relative URL via space_membership_portrait_path with cache-busting.
  #
  # @param participant [SpaceMembership] the membership to display
  # @return [String] HTML for the message avatar
  def mes_avatar(participant)
    content_tag :div, class: "mes-avatar-wrapper" do
      image_tag space_membership_portrait_url(participant),
                class: "avatar",
                alt: participant.display_name
    end
  end

  # Generate URL for space membership portrait with cache-busting.
  #
  # @param participant [SpaceMembership] the membership
  # @return [String] the portrait URL
  def space_membership_portrait_url(participant)
    space_membership_portrait_path(participant.signed_id(purpose: :portrait), v: participant.updated_at.to_fs(:number))
  end

  def participant_portrait_url(participant)
    space_membership_portrait_url(participant)
  end

  # Render a placeholder portrait using default image.
  #
  # @param size [Symbol] portrait size
  # @param css_class [String] additional CSS classes
  # @return [String] HTML for the placeholder
  def placeholder_portrait(size: :md, css_class: "")
    size_class = PORTRAIT_SIZES[size] || PORTRAIT_SIZES[:md]

    content_tag :figure, class: "#{size_class} relative overflow-hidden rounded-lg bg-base-200 shrink-0 #{css_class}" do
      image_tag DEFAULT_PORTRAIT,
                class: "w-full h-full object-cover",
                alt: "Default portrait",
                loading: "lazy"
    end
  end

  # Render a placeholder circular avatar using default image.
  #
  # @param size [Symbol] avatar size
  # @param css_class [String] additional CSS classes
  # @return [String] HTML for the placeholder
  def placeholder_avatar(size: :md, css_class: "")
    size_class = AVATAR_SIZES[size] || AVATAR_SIZES[:md]

    content_tag :div, class: "avatar #{css_class}" do
      content_tag :div, class: "#{size_class} rounded-full overflow-hidden bg-base-200" do
        image_tag DEFAULT_PORTRAIT,
                  class: "w-full h-full object-cover",
                  alt: "Default avatar"
      end
    end
  end
end
