# frozen_string_literal: true

module Settings
  class ApplicationController < ::ApplicationController
    layout "settings"

    before_action :require_administrator
  end
end
