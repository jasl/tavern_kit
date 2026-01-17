require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SELENIUM_HTTP_TIMEOUT = (ENV["SELENIUM_HTTP_TIMEOUT"] || 120).to_i

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
    http_client = Selenium::WebDriver::Remote::Http::Default.new
    http_client.read_timeout = SELENIUM_HTTP_TIMEOUT
    http_client.open_timeout = SELENIUM_HTTP_TIMEOUT

    served_by host: "rails-app", port: ENV["CAPYBARA_SERVER_PORT"]

    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400], options: {
      browser: :remote,
      url: "http://#{ENV["SELENIUM_HOST"]}:4444",
      http_client: http_client,
    }
  else
    http_client = Selenium::WebDriver::Remote::Http::Default.new
    http_client.read_timeout = SELENIUM_HTTP_TIMEOUT
    http_client.open_timeout = SELENIUM_HTTP_TIMEOUT

    driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1400], options: {
      http_client: http_client,
    }
  end
end
