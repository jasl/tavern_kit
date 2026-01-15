# if Rails.env.development?
#   Rails.configuration.after_initialize do
#     Bullet.enable        = true
#     Bullet.alert         = false
#     Bullet.bullet_logger = true
#     Bullet.console       = true
#     Bullet.rails_logger  = true
#     Bullet.add_footer    = true
#   end
# elsif Rails.env.test?
#   Rails.configuration.after_initialize do
#     Bullet.enable        = true
#     Bullet.bullet_logger = true
#     Bullet.raise         = true # raise an error if n+1 query occurs
#   end
# end
#
# if Rails.env.development? || Rails.env.test?
#   Rails.configuration.after_initialize do
#     # Whitelist: Message#active_message_swipe is intentionally eager-loaded via with_space_membership
#     # scope because swipe navigation UI needs it. However, in tests messages often don't have
#     # swipes configured yet, causing false "unused eager loading" warnings.
#     Bullet.add_safelist type: :unused_eager_loading, class_name: "Message", association: :active_message_swipe
#
#     # Whitelist: SpaceMembership associations (user, character) are included as fallbacks
#     # for member/queue rendering, but some code paths only use cached_display_name and
#     # predicates. Bullet may report these as "unused eager loading" in tests.
#     Bullet.add_safelist type: :unused_eager_loading, class_name: "SpaceMembership", association: :user
#     Bullet.add_safelist type: :unused_eager_loading, class_name: "SpaceMembership", association: :character
#
#     # Whitelist: space_memberships is eager-loaded for all Space types in the sidebar switcher,
#     # but Discussion spaces may not access it (only Playground spaces show member count badges).
#     # This is acceptable since most spaces are Playgrounds.
#     Bullet.add_safelist type: :unused_eager_loading, class_name: "Spaces::Discussion", association: :space_memberships
#
#     # Whitelist: forked_from_message is preloaded for tree_conversations to avoid N+1 when
#     # rendering branch navigation. However, root conversations have nil forked_from_message,
#     # so bullet may flag this as unused when testing with root conversations.
#     Bullet.add_safelist type: :unused_eager_loading, class_name: "Conversation", association: :forked_from_message
#
#     # Whitelist: portrait_attachment and blob are eagerly loaded for characters to avoid N+1
#     # when generating fresh_character_portrait_path URLs (which access blob.key for cache busting).
#     # Bullet doesn't track blob.key access so it reports these as unused.
#     Bullet.add_safelist type: :unused_eager_loading, class_name: "Character", association: :portrait_attachment
#     Bullet.add_safelist type: :unused_eager_loading, class_name: "ActiveStorage::Attachment", association: :blob
#   end
# end
