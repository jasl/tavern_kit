# frozen_string_literal: true

# Applies a versioned settings patch to a SpaceMembership.
#
# Used by controller JSON patch updates:
# - optimistic concurrency via settings_version
# - deep-merge for nested settings hashes
#
class SpaceMembership::SettingsPatch
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

    space_membership.with_lock do
      if space_membership.settings_version != expected_version
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

      if payload.key?("settings")
        current_settings = space_membership.settings || {}
        updates[:settings] = current_settings.deep_merge(settings_patch)
      end

      if updates.key?(:settings) || updates.key?(:llm_provider_id)
        updates[:settings_version] = space_membership.settings_version + 1
      end

      unless space_membership.update(updates)
        return Result.new(
          status: :unprocessable_entity,
          body: { ok: false, errors: space_membership.errors.full_messages }
        )
      end
    end

    Result.new(
      status: :ok,
      body: {
        ok: true,
        saved_at: Time.current.iso8601,
        space_membership: space_membership_payload,
      }
    )
  rescue ArgumentError
    Result.new(status: :bad_request, body: { ok: false, errors: ["Invalid llm_provider_id"] })
  end

  private

  attr_reader :space_membership

  def space_membership_payload
    {
      id: space_membership.id,
      llm_provider_id: space_membership.llm_provider_id,
      provider_identification: space_membership.provider_identification,
      settings_version: space_membership.settings_version,
      settings: space_membership.settings,
    }
  end
end
