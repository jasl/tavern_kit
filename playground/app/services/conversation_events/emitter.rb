# frozen_string_literal: true

module ConversationEvents
  module Emitter
    LOG_TAG = "[ConversationEvent]"

    def self.emit(
      event_name:,
      conversation:,
      reason: nil,
      payload: {},
      occurred_at: Time.current,
      space: nil,
      conversation_round_id: nil,
      conversation_run_id: nil,
      trigger_message_id: nil,
      message_id: nil,
      speaker_space_membership_id: nil
    )
      space ||= conversation.space

      event = ConversationEvent.create!(
        event_name: event_name,
        reason: reason,
        payload: normalize_payload(payload),
        occurred_at: occurred_at,
        conversation_id: conversation.id,
        space_id: space.id,
        conversation_round_id: conversation_round_id,
        conversation_run_id: conversation_run_id,
        trigger_message_id: trigger_message_id,
        message_id: message_id,
        speaker_space_membership_id: speaker_space_membership_id
      )

      notification_payload = {
        event_id: event.id,
        event_name: event.event_name,
        reason: event.reason,
        occurred_at: event.occurred_at,
        conversation_id: event.conversation_id,
        space_id: event.space_id,
        conversation_round_id: event.conversation_round_id,
        conversation_run_id: event.conversation_run_id,
        trigger_message_id: event.trigger_message_id,
        message_id: event.message_id,
        speaker_space_membership_id: event.speaker_space_membership_id,
        payload: event.payload,
      }.compact

      ActiveSupport::Notifications.instrument(event.event_name, notification_payload) { event }

      if defined?(Rails) && Rails.logger
        Rails.logger.info("#{LOG_TAG} #{event.event_name} payload=#{notification_payload.to_json}")
      end

      event
    rescue StandardError => e
      if defined?(Rails) && Rails.logger
        Rails.logger.error("#{LOG_TAG} failed event_name=#{event_name} error=#{e.class}: #{e.message}")
      end
      nil
    end

    def self.normalize_payload(payload)
      normalized = payload.respond_to?(:compact) ? payload.compact : payload
      (normalized || {}).as_json
    end
    private_class_method :normalize_payload
  end
end
