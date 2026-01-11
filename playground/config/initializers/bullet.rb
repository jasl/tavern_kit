if Rails.env.development? || Rails.env.test?
  Rails.configuration.after_initialize do
    # Whitelist: Message#active_message_swipe is intentionally eager-loaded via with_space_membership
    # scope because swipe navigation UI needs it. However, in tests messages often don't have
    # swipes configured yet, causing false "unused eager loading" warnings.
    Bullet.add_safelist type: :unused_eager_loading, class_name: "Message", association: :active_message_swipe

    # Whitelist: SpaceMembership associations (user, character) are included as fallbacks
    # for display_name when cached_display_name is blank (legacy records). Since new
    # records always have cached_display_name set via before_create callback, these
    # associations are rarely accessed, but the eager loading is intentional for
    # backwards compatibility.
    Bullet.add_safelist type: :unused_eager_loading, class_name: "SpaceMembership", association: :user
    Bullet.add_safelist type: :unused_eager_loading, class_name: "SpaceMembership", association: :character

    # Whitelist: space_memberships is eager-loaded for all Space types in the sidebar switcher,
    # but Discussion spaces may not access it (only Playground spaces show member count badges).
    # This is acceptable since most spaces are Playgrounds.
    Bullet.add_safelist type: :unused_eager_loading, class_name: "Spaces::Discussion", association: :space_memberships

    # Whitelist: forked_from_message is preloaded for tree_conversations to avoid N+1 when
    # rendering branch navigation. However, root conversations have nil forked_from_message,
    # so bullet may flag this as unused when testing with root conversations.
    Bullet.add_safelist type: :unused_eager_loading, class_name: "Conversation", association: :forked_from_message
  end
end
