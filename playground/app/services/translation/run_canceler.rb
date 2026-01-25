# frozen_string_literal: true

module Translation
  class RunCanceler
    def self.cancel_active_for_space!(space:, reason:)
      new(space: space, reason: reason).cancel_active_for_space!
    end

    def initialize(space:, reason:)
      @space = space
      @reason = reason.to_s
    end

    def cancel_active_for_space!
      TranslationRun
        .active
        .joins(:conversation)
        .where(conversations: { space_id: space.id })
        .find_each do |run|
          cancel_run!(run)
        end
    end

    private

    attr_reader :space, :reason

    def cancel_run!(run)
      return unless run.can_cancel?

      record = run.target_record
      Translation::Metadata.clear_pending!(record, target_lang: run.target_lang) if record && run.target_lang.present?

      run.canceled!(error: { "code" => reason, "message" => "Canceled (#{reason})" })

      ConversationEvents::Emitter.emit(
        event_name: "translation_run.canceled",
        conversation: run.conversation,
        space: space,
        message_id: run.message_id,
        reason: reason,
        payload: {
          translation_run_id: run.id,
          message_swipe_id: run.message_swipe_id,
          source_lang: run.source_lang,
          internal_lang: run.internal_lang,
          target_lang: run.target_lang,
          debug: run.debug,
          error: run.error,
        }
      )

      run.message.broadcast_update if run.message
    rescue StandardError => e
      Rails.logger.warn "[Translation::RunCanceler] Failed to cancel run #{run.id}: #{e.class}: #{e.message}"
    end
  end
end
