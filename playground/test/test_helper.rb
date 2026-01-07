ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

require "mocha/minitest"

# Load test helpers
Dir[Rails.root.join("test/test_helpers/**/*.rb")].each { |f| require f }

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper

    # Default to running in parallel using all cores.
    # Override with `PARALLEL_WORKERS=...` (set to 0/1 to disable parallelization).
    parallel_workers_env = ENV["PARALLEL_WORKERS"]
    if parallel_workers_env
      parallel_workers = parallel_workers_env.to_i
      parallelize(workers: parallel_workers, threshold: 50) if parallel_workers > 1
    else
      parallelize(workers: :number_of_processors, threshold: 50)
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Include test helpers
    include SessionTestHelper
    include TurboTestHelper

    # Add more helper methods to be used by all tests here...
  end
end
