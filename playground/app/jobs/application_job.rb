class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  ROUTES_LOAD_MUTEX = Mutex.new

  private

  # SolidQueue can execute jobs concurrently in a fresh worker process before
  # Rails routes have been loaded. Rendering Turbo Stream partials relies on
  # route helpers being available, and Rails' route loader isn't thread-safe
  # during lazy loading in multi-threaded contexts.
  #
  # We ensure routes are loaded once, under a global mutex, before any job
  # attempts to render/broadcast view templates that reference *_path helpers.
  def ensure_routes_loaded_for_rendering!
    return unless Rails.env.development?
    return if Rails.application.routes_reloader.loaded

    ROUTES_LOAD_MUTEX.synchronize do
      return if Rails.application.routes_reloader.loaded

      Rails.application.routes_reloader.execute_unless_loaded
    end
  end
end
