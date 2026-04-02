require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"
  enable_coverage :branch
  minimum_coverage line: 80
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# Disable Rack::Attack throttling in tests to avoid rate limit interference
Rack::Attack.enabled = false

module ActiveSupport
  class TestCase
    # Disable parallel for accurate coverage. Re-enable if test suite gets slow.
    # parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
