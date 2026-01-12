# frozen_string_literal: true

require "json"
require "stringio"
require "time"

module TurnSchedulerProfiling
  PerfEvent = Struct.new(:label, :total_ms, :sql_count, :sql_ms, :payload, keyword_init: true)

  class NullJobProxy
    def perform_later(*)
      nil
    end
  end

  class FakeLLMClient
    Provider = Struct.new(:name, :identification, :model, :streamable?, keyword_init: true)

    attr_reader :provider, :last_usage, :last_logprobs

    def initialize
      @provider = Provider.new(
        name: "Fake (No-HTTP)",
        identification: "openai_compatible",
        model: "fake",
        streamable?: false
      )
      @last_usage = nil
      @last_logprobs = nil
    end

    def chat(messages:, **)
      last_user = messages.reverse.find { |m| m[:role].to_s == "user" || m["role"].to_s == "user" }
      content = last_user ? (last_user[:content] || last_user["content"]).to_s : "..."
      "ACK: #{content}"
    end
  end

  class << self
    def run_typical!(reply_order:, ai_count:, user_message:)
      original_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :inline

      original_logger = Rails.logger
      log_io = StringIO.new

      logger = Logger.new(log_io)
      logger.level = Logger::DEBUG
      logger.formatter = proc { |_severity, _time, _progname, msg| "#{msg}\n" }
      Rails.logger = logger

      original_env = ENV["TURN_SCHEDULER_PROFILE"]
      ENV["TURN_SCHEDULER_PROFILE"] = "1"

      original_llm_new = LLMClient.singleton_class.instance_method(:new)
      LLMClient.singleton_class.send(:define_method, :new) do |provider: nil|
        FakeLLMClient.new
      end

      # RunExecutor schedules a long-delay safety reaper job via `set(wait: ...)`.
      # InlineAdapter cannot enqueue jobs "in the future", so we disable the reaper
      # for this profiling task (the run is executed synchronously anyway).
      original_reaper_set = nil
      original_reaper_set = ConversationRunReaperJob.singleton_class.instance_method(:set)
      ConversationRunReaperJob.singleton_class.send(:define_method, :set) do |*_args, **_kwargs|
        NullJobProxy.new
      end

      run_ids = []
      space = nil

      begin
        user = User.create!(name: "TS Profiler", password: SecureRandom.hex(16), role: "administrator")

        characters = ai_count.times.map do |idx|
          Character.create!(
            name: "AI #{idx + 1}",
            status: "ready",
            spec_version: 3,
            data: { name: "AI #{idx + 1}", description: "Profiling character #{idx + 1}" },
            user: user,
            visibility: "private"
          )
        end

        space = Spaces::Playground.create!(
          name: "TS Profile #{Time.current.utc.iso8601}",
          owner: user,
          reply_order: reply_order,
          auto_mode_delay_ms: 0,
          user_turn_debounce_ms: 0,
          during_generation_user_input_policy: "reject",
          visibility: "private"
        )

        human = space.space_memberships.create!(
          kind: "human",
          role: "owner",
          user: user,
          position: 0
        )

        characters.each_with_index do |character, idx|
          space.space_memberships.create!(
            kind: "character",
            role: "member",
            character: character,
            position: idx + 1
          )
        end

        conversation = space.conversations.create!(title: "TurnScheduler Profiling")

        conversation.messages.create!(
          space_membership: human,
          role: "user",
          content: user_message
        )

        run_ids = ConversationRun.where(conversation: conversation).pluck(:id)
      ensure
        # Stop capturing logs before cleanup to keep perf output focused.
        Rails.logger = original_logger

        # Cleanup test data (best-effort).
        space&.destroy
      end

      {
        log_output: log_io.string,
        run_ids: run_ids,
      }
    ensure
      ActiveJob::Base.queue_adapter = original_adapter

      ENV["TURN_SCHEDULER_PROFILE"] = original_env

      LLMClient.singleton_class.send(:define_method, :new, original_llm_new)
      if original_reaper_set
        ConversationRunReaperJob.singleton_class.send(:define_method, :set, original_reaper_set)
      end

      Rails.logger = original_logger
    end

    def parse_perf_events(log_output)
      return [] if log_output.blank?

      log_output.each_line.filter_map do |line|
        next unless line.include?("[TurnScheduler::Perf]")

        payload_json = line.split("payload=", 2)[1]&.strip

        if (m = line.match(/\[TurnScheduler::Perf\]\s+(\S+)\s+total_ms=([0-9.]+)\s+sql_count=(\d+)\s+sql_ms=([0-9.]+)/))
          PerfEvent.new(
            label: m[1],
            total_ms: m[2].to_f,
            sql_count: m[3].to_i,
            sql_ms: m[4].to_f,
            payload: parse_json_payload(payload_json)
          )
        end
      end
    end

    def parse_json_payload(payload_json)
      return nil if payload_json.blank?

      JSON.parse(payload_json)
    rescue JSON::ParserError
      payload_json
    end

    def summarize(events)
      by_label = events.group_by(&:label)

      by_label.keys.sort.map do |label|
        group = by_label[label]
        slowest = group.max_by(&:total_ms)

        {
          label: label,
          count: group.size,
          total_ms_avg: avg(group.map(&:total_ms)),
          total_ms_max: slowest.total_ms,
          sql_count_avg: avg(group.map(&:sql_count)),
          sql_count_max: group.map(&:sql_count).max,
          sql_ms_avg: avg(group.map(&:sql_ms)),
          sql_ms_max: group.map(&:sql_ms).max,
          slowest_payload: slowest.payload
        }
      end
    end

    def avg(values)
      return 0.0 if values.empty?

      values.sum.to_f / values.size
    end

    def markdown_entry(reply_order:, ai_count:, user_message:, run_ids:, summary:, raw_lines:)
      now = Time.current
      date = now.strftime("%Y-%m-%d")
      stamp = now.utc.iso8601
      sha = `git rev-parse --short HEAD 2>/dev/null`.to_s.strip
      sha = nil if sha.blank?

      header = +"#### #{date} (#{stamp} / #{Rails.env}#{sha ? " / #{sha}" : ""})\n\n"
      header << "Scenario:\n"
      header << "- reply_order=#{reply_order}\n"
      header << "- ai_count=#{ai_count}\n"
      header << "- user_message=#{user_message.inspect}\n"
      header << "- runs_created=#{run_ids.size}\n\n"

      header << "Key perf summary:\n"
      summary.each do |row|
        header << "- #{row[:label]}: n=#{row[:count]} total_ms avg=#{row[:total_ms_avg].round(1)} max=#{row[:total_ms_max].round(1)} " \
                  "sql_count avg=#{row[:sql_count_avg].round(1)} max=#{row[:sql_count_max]} " \
                  "sql_ms avg=#{row[:sql_ms_avg].round(1)} max=#{row[:sql_ms_max].round(1)}\n"

        payload = row[:slowest_payload]
        next if payload.blank?

        header << "  - slowest payload: #{payload.is_a?(String) ? payload : payload.to_json}\n"
      end

      header << "\nRaw [TurnScheduler::Perf] lines:\n\n"
      header << "```\n"
      raw_lines.each { |line| header << line }
      header << "```\n"

      header << "\nConclusions:\n- ...\n\nFollow-ups:\n- ...\n"
      header
    end

    def write_markdown(entry, out_path:, append:)
      if out_path.present?
        mode = append ? "a" : "w"
        File.open(out_path, mode) do |f|
          f.write("\n\n") if append && f.size.positive?
          f.write(entry)
        end
        puts "Wrote profiling markdown to #{out_path}"
      else
        puts entry
      end
    end
  end
end

namespace :turn_scheduler do
  desc "Run a no-browser typical interaction and summarize [TurnScheduler::Perf] to markdown (uses a fake no-HTTP LLM client)."
  task profile_typical: :environment do
    reply_order = ENV.fetch("REPLY_ORDER", "list")
    ai_count = ENV.fetch("AI_COUNT", "2").to_i
    user_message = ENV.fetch("USER_MESSAGE", "Hello (profiling)")

    out_path = ENV["OUT"]
    append = ENV["APPEND"] == "1"

    result = TurnSchedulerProfiling.run_typical!(
      reply_order: reply_order,
      ai_count: ai_count,
      user_message: user_message
    )

    events = TurnSchedulerProfiling.parse_perf_events(result[:log_output])
    summary = TurnSchedulerProfiling.summarize(events)

    raw_lines = result[:log_output].each_line.select { |l| l.include?("[TurnScheduler::Perf]") }
    entry = TurnSchedulerProfiling.markdown_entry(
      reply_order: reply_order,
      ai_count: ai_count,
      user_message: user_message,
      run_ids: result[:run_ids],
      summary: summary,
      raw_lines: raw_lines
    )

    TurnSchedulerProfiling.write_markdown(entry, out_path: out_path, append: append)
  end
end
