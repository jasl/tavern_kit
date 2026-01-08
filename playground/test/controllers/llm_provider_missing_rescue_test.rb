# frozen_string_literal: true

require "test_helper"

class LLMProviderMissingTestController < ApplicationController
  allow_unauthenticated_access

  def index
    LLMClient.new.chat(messages: [{ role: "user", content: "Hello" }])
    render plain: "ok"
  end

  def root
    render plain: "root"
  end
end

class LLMProviderMissingRescueTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin
    LLMProvider.delete_all
    Setting.delete("llm.default_provider_id")
  end

  test "ApplicationController rescues NoProviderError with a friendly message" do
    with_routing do |set|
      set.draw do
        root to: "llm_provider_missing_test#root"
        get "/no_provider", to: "llm_provider_missing_test#index"
      end

      get "/no_provider"
      assert_response :redirect
      assert_redirected_to root_url

      expected =
        I18n.t(
          "llm_providers.errors.no_default_provider",
          default: "No LLM provider configured. Please set a default provider in Settings."
        )
      assert_equal expected, flash[:alert]
    end
  end
end
