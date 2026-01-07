require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # System tests drive the app through a real browser. We want "immediate" jobs
  # (ConversationRunJob, etc.) to run automatically, but we **do not** want to run
  # scheduled jobs (e.g. ConversationRunReaperJob scheduled via enqueue_at).
  #
  # We achieve this by keeping the default :test adapter and enabling
  # perform_enqueued_jobs (but not perform_enqueued_at_jobs) for the duration of each test.
  setup do
    adapter = ActiveJob::Base.queue_adapter
    return unless adapter.respond_to?(:perform_enqueued_jobs=) && adapter.respond_to?(:perform_enqueued_at_jobs=)

    @original_perform_enqueued_jobs = adapter.perform_enqueued_jobs
    @original_perform_enqueued_at_jobs = adapter.perform_enqueued_at_jobs
    adapter.perform_enqueued_jobs = true
    adapter.perform_enqueued_at_jobs = false
  end

  teardown do
    adapter = ActiveJob::Base.queue_adapter
    if adapter.respond_to?(:perform_enqueued_jobs=) && defined?(@original_perform_enqueued_jobs)
      adapter.perform_enqueued_jobs = @original_perform_enqueued_jobs
    end
    if adapter.respond_to?(:perform_enqueued_at_jobs=) && defined?(@original_perform_enqueued_at_jobs)
      adapter.perform_enqueued_at_jobs = @original_perform_enqueued_at_jobs
    end
  end

  if ENV["CAPYBARA_SERVER_PORT"]
    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444",
    }
  else
    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400]
  end
end
