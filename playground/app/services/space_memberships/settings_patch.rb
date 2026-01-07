# frozen_string_literal: true

# Applies a versioned settings patch to a SpaceMembership.
#
# Concurrency Strategy:
# Uses true optimistic locking without pessimistic locks.
# The settings_version column acts as a version counter:
# - Client sends expected version with update
# - Update uses WHERE condition on version
# - If 0 rows updated, another request modified the record (conflict)
#
# This eliminates database row locks and prevents deadlocks.
#
module SpaceMemberships
  class SettingsPatch
    Result = Data.define(:status, :body) do
      def ok? = status == :ok
    end

    def initialize(space_membership)
      @space_membership = space_membership
    end

    def call(payload)
      settings_version = payload["settings_version"]
      llm_provider_id_value = payload["llm_provider_id"]
      settings_patch = payload["settings"]

      if settings_version.nil?
        return Result.new(status: :bad_request, body: { ok: false, errors: ["Missing settings_version"] })
      end

      unless payload.key?("llm_provider_id") || payload.key?("settings")
        return Result.new(status: :bad_request, body: { ok: false, errors: ["Missing llm_provider_id or settings"] })
      end

      llm_provider_id =
        if payload.key?("llm_provider_id")
          if llm_provider_id_value.blank?
            nil
          else
            Integer(llm_provider_id_value)
          end
        end

      if payload.key?("settings") && !settings_patch.is_a?(Hash)
        return Result.new(status: :bad_request, body: { ok: false, errors: ["settings must be an object"] })
      end

      expected_version = settings_version.to_i

      updates = {}
      updates[:llm_provider_id] = llm_provider_id if payload.key?("llm_provider_id")

      if payload.key?("settings")
        current_settings = space_membership.settings || ConversationSettings::ParticipantSettings.new
        current_hash = current_settings.respond_to?(:to_h) ? current_settings.to_h.deep_stringify_keys : current_settings.to_h
        updates[:settings] = current_hash.deep_merge(settings_patch)
      end

      return result_ok if updates.empty?

      updates[:settings_version] = expected_version + 1
      updates[:updated_at] = Time.current

      updated_count = SpaceMembership
        .where(id: space_membership.id, settings_version: expected_version)
        .update_all(updates)

      if updated_count == 0
        space_membership.reload
        return Result.new(
          status: :conflict,
          body: {
            ok: false,
            conflict: true,
            errors: ["Settings have changed. Please refresh and try again."],
            space_membership: space_membership_payload,
          }
        )
      end

      space_membership.reload
      result_ok
    rescue ArgumentError
      Result.new(status: :bad_request, body: { ok: false, errors: ["Invalid llm_provider_id"] })
    end

    private

    attr_reader :space_membership

    def result_ok
      Result.new(
        status: :ok,
        body: {
          ok: true,
          saved_at: Time.current.iso8601,
          space_membership: space_membership_payload,
        }
      )
    end

    def space_membership_payload
      settings_hash = space_membership.settings
      settings_hash = settings_hash.to_h if settings_hash.respond_to?(:to_h)

      {
        id: space_membership.id,
        llm_provider_id: space_membership.llm_provider_id,
        provider_identification: space_membership.provider_identification,
        settings_version: space_membership.settings_version,
        settings: settings_hash,
      }
    end
  end
end
