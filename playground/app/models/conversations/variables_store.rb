# frozen_string_literal: true

module Conversations
  # ChatVariables-compatible store backed by conversation.variables jsonb.
  # Must implement get/set (not just []/[]=) because macro engine calls get/set directly.
  class VariablesStore < TavernKit::ChatVariables::Base
    def initialize(conversation)
      @conversation = conversation
    end

    def get(key)
      variables_hash[key.to_s]
    end
    alias [] get

    def set(key, value)
      key = key.to_s
      variables_hash[key] = value

      persist_set!(key, value) if @conversation.persisted?
      value
    end
    alias []= set

    def delete(key)
      key = key.to_s
      result = variables_hash.delete(key)

      persist_delete!(key) if @conversation.persisted?
      result
    end

    def key?(key)
      variables_hash.key?(key.to_s)
    end

    def each(&block)
      return to_enum(:each) unless block_given?

      variables_hash.each(&block)
    end

    def size
      variables_hash.size
    end

    def clear
      variables_hash.clear
      persist_clear! if @conversation.persisted?
      self
    end

    private

    def variables_hash
      @conversation.variables ||= {}
    end

    # Persist a single key update atomically (jsonb_set) to avoid lost updates
    # when multiple processes update different keys concurrently.
    def persist_set!(key, value)
      now = Time.current

      Conversation.where(id: @conversation.id).update_all([
        "variables = jsonb_set(COALESCE(variables, '{}'::jsonb), ARRAY[?]::text[], ?::jsonb, true), updated_at = ?",
        key,
        value.to_json,
        now,
      ])

      @conversation.updated_at = now
    end

    # Persist a single key delete atomically (jsonb - key).
    def persist_delete!(key)
      now = Time.current

      Conversation.where(id: @conversation.id).update_all([
        "variables = COALESCE(variables, '{}'::jsonb) - ?, updated_at = ?",
        key,
        now,
      ])

      @conversation.updated_at = now
    end

    def persist_clear!
      now = Time.current

      Conversation.where(id: @conversation.id).update_all(variables: {}, updated_at: now)
      @conversation.updated_at = now
    end
  end
end
