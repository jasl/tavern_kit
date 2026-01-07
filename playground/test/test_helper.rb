ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require "mocha/minitest"

# Load test helpers
Dir[Rails.root.join("test/test_helpers/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # Run tests in parallel with specified workers
    # Limit to 2 workers to avoid database connection pool exhaustion
    # and lock contention during concurrent tests
    parallelize(workers: ENV.fetch("PARALLEL_WORKERS", 2).to_i, threshold: 50)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Include test helpers
    include SessionTestHelper
    include TurboTestHelper

    # Add more helper methods to be used by all tests here...
  end
end
