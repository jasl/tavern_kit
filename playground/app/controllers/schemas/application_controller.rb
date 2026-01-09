# frozen_string_literal: true

module Schemas
  class ApplicationController < ActionController::API
    include ActionController::ConditionalGet
  end
end
