# frozen_string_literal: true

require "test_helper"

class LLMModelMissingTestController < ApplicationController
  allow_unauthenticated_access

  def index
    provider =
      LLMProvider.create!(
        name: "Model Missing Provider",
        identification: "openai_compatible",
        base_url: "https://api.example.com/v1",
        model: nil,
        streamable: true,
        disabled: false
      )

    LLMClient.new(provider: provider).chat(messages: [{ role: "user", content: "Hello" }])
    render plain: "ok"
  end

  def root
    render plain: "root"
  end
end

class LLMModelMissingRescueTest < ActionDispatch::IntegrationTest
  setup do
    sign_in :admin
  end

  test "ApplicationController rescues ModelMissingError with a friendly message" do
    with_routing do |set|
      set.draw do
        root to: "llm_model_missing_test#root"
        get "/model_missing", to: "llm_model_missing_test#index"
      end

      get "/model_missing"
      assert_response :redirect
      assert_redirected_to root_url

      expected =
        I18n.t(
          "llm_providers.errors.model_missing",
          default: "No model configured for the selected LLM provider. Please set a model in Settings."
        )
      assert_equal expected, flash[:alert]
    end
  end
end
