# frozen_string_literal: true

module TurnScheduler
  # Lightweight opt-in profiling for TurnScheduler hot paths.
  #
  # Enable by setting `TURN_SCHEDULER_PROFILE=1`.
  #
  # This is intentionally a no-op by default to avoid overhead in production.
  module Instrumentation
    SQL_EVENT = "sql.active_record"
    IGNORED_SQL_NAMES = %w[SCHEMA TRANSACTION].freeze

    def self.enabled?
      ENV["TURN_SCHEDULER_PROFILE"].present?
    end

    def self.profile(label, payload = {})
      return yield unless enabled?

      sql_count = 0
      sql_ms = 0.0
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      callback = lambda do |_name, started, finished, _unique_id, data|
        next if IGNORED_SQL_NAMES.include?(data[:name])

        sql_count += 1
        # ActiveSupport::Notifications provides timing via the started/finished args,
        # not in the payload hash.
        sql_ms += (finished - started) * 1000.0
      end

      ActiveSupport::Notifications.subscribed(callback, SQL_EVENT) do
        result = yield
        total_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0

        if defined?(Rails) && Rails.logger
          payload = payload.respond_to?(:compact) ? payload.compact : payload
          Rails.logger.info(
            "[TurnScheduler::Perf] #{label} total_ms=#{total_ms.round(1)} sql_count=#{sql_count} sql_ms=#{sql_ms.round(1)} payload=#{payload.to_json}"
          )
        end

        result
      end
    end
  end
end
