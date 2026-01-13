# SimpleCov must be loaded before anything else
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "rails" do
    # Track coverage for app code only
    add_filter "/test/"
    add_filter "/config/"
    add_filter "/db/"
    add_filter "/vendor/"

    # Group coverage by component type
    add_group "Controllers", "app/controllers"
    add_group "Models", "app/models"
    add_group "Services", "app/services"
    add_group "Jobs", "app/jobs"
    add_group "Channels", "app/channels"
    add_group "Helpers", "app/helpers"
    add_group "Presenters", "app/presenters"

    # Set minimum coverage threshold (optional, set to 0 initially)
    # minimum_coverage 80
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require "mocha/minitest"

# Load test helpers
Dir[Rails.root.join("test/test_helpers/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # SimpleCov does not automatically merge coverage across Rails parallel test workers.
    # Run in a single process when COVERAGE is enabled so the report is trustworthy.
    unless ENV["COVERAGE"]
    # Default to running in parallel using all cores.
    # Override with `PARALLEL_WORKERS=...` (set to 0/1 to disable parallelization).
    parallel_workers_env = ENV["PARALLEL_WORKERS"]
    if parallel_workers_env
      parallel_workers = parallel_workers_env.to_i
      parallelize(workers: parallel_workers, threshold: 50) if parallel_workers > 1
    else
      parallelize(workers: :number_of_processors, threshold: 50)
    end
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Include test helpers
    include SessionTestHelper
    include TurboTestHelper

    # Add more helper methods to be used by all tests here...
  end
end
