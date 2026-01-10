# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  config.after_initialize do
    Bullet.enable        = true
    Bullet.bullet_logger = true
    Bullet.raise         = true # raise an error if n+1 query occurs

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

  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?
  config.rake_eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  # config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  # config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
