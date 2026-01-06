# frozen_string_literal: true

# Custom coder for ActiveRecord serialize that converts between
# JSONB (Hash) and EasyTalk::Schema objects.
#
# Database constraint guarantees data is always a JSON object (Hash),
# so we can safely assume non-nil values are Hashes.
#
# @example
#   serialize :data, coder: EasyTalkCoder.new(TavernKit::Character::Schema)
#
class EasyTalkCoder
  def initialize(schema_class)
    @schema_class = schema_class
  end

  # Convert Schema object to Hash for database storage
  # DB constraint requires object, so return {} instead of nil
  def dump(obj)
    return {} if obj.nil?

    obj.respond_to?(:to_h) ? obj.to_h : obj.to_hash
  end

  # Convert Hash from database to Schema object
  # DB constraint guarantees this is a Hash (object), never nil
  def load(hash)
    hash ||= {} # Safety fallback, but DB constraint should prevent nil
    return hash if hash.is_a?(@schema_class)

    @schema_class.new(hash.deep_symbolize_keys)
  end
end
