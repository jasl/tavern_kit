# frozen_string_literal: true

module Lockable
  extend ActiveSupport::Concern

  included do
    before_update :prevent_update_when_locked
    before_destroy :prevent_destroy_when_locked
  end

  def locked?
    locked_at.present?
  end

  # Lock the record (bypasses before_update callback).
  # @return [Boolean] true if the update succeeded
  def lock!
    update_column(:locked_at, Time.current)
  end

  # Unlock the record (bypasses before_update callback).
  # @return [Boolean] true if the update succeeded
  def unlock!
    update_column(:locked_at, nil)
  end

  private

  def prevent_update_when_locked
    return unless locked?

    errors.add(:base, "Record is locked")
    throw :abort
  end

  def prevent_destroy_when_locked
    return unless locked?

    errors.add(:base, "Record is locked")
    throw :abort
  end
end
