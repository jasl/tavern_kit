# frozen_string_literal: true

# Concern for models that can be duplicated (create a copy).
#
# Provides a standard interface for creating copies of records.
# Each including model must implement `#copy_attributes` and optionally
# `#after_copy` to handle model-specific copying logic.
#
# @example Basic usage
#   class Preset < ApplicationRecord
#     include Duplicatable
#
#     private
#
#     def copy_attributes
#       {
#         name: "#{name} (Copy)",
#         description: description,
#         # ... other attributes
#       }
#     end
#   end
#
#   copy = preset.create_copy!
#   copy.name # => "My Preset (Copy)"
#
# @example With after_copy hook for associations
#   class Lorebook < ApplicationRecord
#     include Duplicatable
#
#     private
#
#     def copy_attributes
#       { name: "#{name} (Copy)", ... }
#     end
#
#     def after_copy(copy)
#       entries.each do |entry|
#         copy.entries.create!(entry.copyable_attributes)
#       end
#     end
#   end
#
module Duplicatable
  extend ActiveSupport::Concern

  # Create a saved copy of this record.
  #
  # Uses `copy_attributes` to build the new record and `after_copy` for
  # post-save operations like copying associations.
  #
  # @param overrides [Hash] attributes to override in the copy
  # @return [ApplicationRecord] the saved copy
  # @raise [ActiveRecord::RecordInvalid] if the copy fails validation
  def create_copy!(**overrides)
    attributes = copy_attributes.merge(overrides)
    copy = self.class.new(attributes)

    self.class.transaction do
      copy.save!
      after_copy(copy) if respond_to?(:after_copy, true)
    end

    copy
  end

  # Create a copy of this record (does not raise on failure).
  #
  # @param overrides [Hash] attributes to override in the copy
  # @return [ApplicationRecord] the copy (may have errors if save failed)
  def create_copy(**overrides)
    attributes = copy_attributes.merge(overrides)
    copy = self.class.new(attributes)

    self.class.transaction do
      if copy.save
        after_copy(copy) if respond_to?(:after_copy, true)
      end
    end

    copy
  end

  private

  # Returns attributes for the copy. Must be implemented by including class.
  #
  # @return [Hash] attributes for the new record
  # @raise [NotImplementedError] if not implemented
  def copy_attributes
    raise NotImplementedError, "#{self.class} must implement #copy_attributes"
  end
end
