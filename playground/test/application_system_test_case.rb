require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SELENIUM_HTTP_TIMEOUT = (ENV["SELENIUM_HTTP_TIMEOUT"] || 120).to_i

  # System tests run a real Puma server. These tests also run background jobs that
  # make HTTP requests back into the app (Mock LLM at /mock_llm/v1). With a low
  # Puma thread count, websocket connections + Turbo can exhaust threads and
  # deadlock those internal requests (manifesting as Net::ReadTimeout).
  #
  # Increase Puma threads to keep system tests reliable.
  Capybara.server = :puma, { Threads: "0:10", Silent: true }

  # System tests drive the app through a real browser. We want "immediate" jobs
  # (ConversationRunJob, etc.) to be explicitly controlled (via `perform_enqueued_jobs`)
  # to avoid deadlocks when jobs make HTTP requests back into the Capybara server.
  #
  # We **do not** want to run scheduled jobs (e.g. ConversationRunReaperJob scheduled via enqueue_at).
  #
  # We achieve this by keeping the default :test adapter and disabling both
  # auto-perform flags for the duration of each test.
  setup do
    adapter = ActiveJob::Base.queue_adapter
    return unless adapter.respond_to?(:perform_enqueued_jobs=) && adapter.respond_to?(:perform_enqueued_at_jobs=)

    @original_perform_enqueued_jobs = adapter.perform_enqueued_jobs
    @original_perform_enqueued_at_jobs = adapter.perform_enqueued_at_jobs
    adapter.perform_enqueued_jobs = false
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

  protected

  def wait_for_enqueued_job(job_class, timeout: 10)
    deadline = Time.current + timeout
    adapter = ActiveJob::Base.queue_adapter

    loop do
      return if adapter.enqueued_jobs.any? { |j| j[:job] == job_class }

      raise "Timed out waiting for #{job_class} to enqueue" if Time.current > deadline

      sleep 0.05
    end
  end

  # Run ConversationRunJob(s) until the TurnScheduler finishes the queued runs.
  #
  # This is useful in system tests because we disable auto-performing jobs (see setup),
  # to avoid deadlocks when jobs make HTTP requests back into the Capybara server.
  def drain_conversation_run_jobs!(conversation, max_runs: 10, timeout: 10)
    adapter = ActiveJob::Base.queue_adapter

    max_runs.times do
      conversation.reload
      has_queued_run = conversation.conversation_runs.queued.exists?
      has_enqueued_job = adapter.enqueued_jobs.any? { |j| j[:job] == ConversationRunJob }

      break unless has_queued_run || has_enqueued_job

      wait_for_enqueued_job(ConversationRunJob, timeout: timeout) if has_queued_run && !has_enqueued_job

      # System tests disable `perform_enqueued_at_jobs` to avoid running scheduled
      # maintenance jobs. However, `ConversationRunJob` is sometimes intentionally
      # enqueued via `enqueue_at` (e.g. debounce/delay). We still need to run it
      # to complete the round.
      #
      # Execute only `ConversationRunJob` from the test adapter queue (including
      # jobs with `:at`), and remove them from the queue as we go.
      loop do
        idx = adapter.enqueued_jobs.find_index { |j| j[:job] == ConversationRunJob }
        break unless idx

        job = adapter.enqueued_jobs.delete_at(idx)
        args = Array(job[:args])
        at = job[:at]

        # If the job was enqueued via `enqueue_at`, fast-forward time so the run
        # becomes ready (RunExecutor will otherwise reschedule and return).
        if at.present?
          due_at = Time.at(at)
          if due_at > Time.current
            travel_to(due_at + 0.001) { ConversationRunJob.perform_now(*args) }
            next
          end
        end

        # ActiveJob::QueueAdapters::TestAdapter stores args in the same order as
        # originally enqueued. For ConversationRunJob it's typically `[run_id]`.
        ConversationRunJob.perform_now(*args)
      end
    end

    conversation.reload

    if conversation.conversation_runs.queued.exists?
      raise(
        "drain_conversation_run_jobs! did not drain all queued runs. " \
        "queued_ids=#{conversation.conversation_runs.queued.pluck(:id)} " \
        "failed_ids=#{conversation.conversation_runs.failed.pluck(:id)}"
      )
    end

    if conversation.conversation_runs.failed.exists?
      recent =
        conversation.conversation_runs.failed.order(id: :desc).limit(3).map do |run|
          code = run.error.is_a?(Hash) ? run.error["code"] : nil
          msg = run.error.is_a?(Hash) ? run.error["message"] : nil
          "id=#{run.id} code=#{code.inspect} message=#{msg.inspect}"
        end

      raise("drain_conversation_run_jobs! observed failed run(s): #{recent.join(" | ")}")
    end
  end
end
