Rails.application.config.session_store :cookie_store,
  key: "_tavern_session",
  expire_after: 2.weeks
