# frozen_string_literal: true

# Lightweight `ServiceResponse` inspired by GitLab's convention.
#
# Contract:
# - Services expose a single public `#execute` method.
# - `#execute` returns a `ServiceResponse`.
# - Callers branch on `success?/error?` and optionally `reason`.
class ServiceResponse
  def self.success(message: nil, payload: {}, http_status: :ok, reason: nil)
    new(
      status: :success,
      message: message,
      payload: payload,
      http_status: http_status,
      reason: reason
    )
  end

  def self.error(message:, payload: {}, http_status: nil, reason: nil)
    new(
      status: :error,
      message: message,
      payload: payload,
      http_status: http_status,
      reason: reason
    )
  end

  # Wraps old service responses that were hashes.
  def self.from_legacy_hash(response)
    return response if response.is_a?(ServiceResponse)
    return new(**response) if response.is_a?(Hash)

    raise ArgumentError, "argument must be a ServiceResponse or a Hash"
  end

  attr_reader :status, :message, :http_status, :payload, :reason

  def initialize(status:, message: nil, payload: {}, http_status: nil, reason: nil)
    self.status = status
    self.message = message
    self.payload = payload
    self.http_status = http_status
    self.reason = reason
  end

  def [](key)
    to_h[key]
  end

  def to_h
    (payload || {}).merge(
      status: status,
      message: message,
      http_status: http_status,
      reason: reason
    )
  end

  def deconstruct_keys(keys)
    to_h.slice(*keys)
  end

  def success?
    status == :success
  end

  def error?
    status == :error
  end

  def errors
    return [] unless error?

    Array.wrap(message)
  end

  # Convenience for branching:
  #
  # ```
  # return if response.cause.paused_blocked?
  # ```
  def cause
    ActiveSupport::StringInquirer.new(reason.to_s)
  end

  private

  attr_writer :status, :message, :http_status, :payload, :reason
end
