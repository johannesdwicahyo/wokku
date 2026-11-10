# frozen_string_literal: true

# SimpleCov FIRST — before any engine code loads. Measures ONLY the engine
# (app/ + lib/ at the repo root); the harness test host and specs are
# filtered out. The 95% line gate lives in CI (rake or the workflow) once
# the suite is fully migrated; here we just collect coverage.
require "ostruct" # Ruby 3.4 dropped it from autoload; specs use it
require "simplecov"
SimpleCov.start do
  # One result per parallel_tests worker ("" for worker 1, "2".."N" after),
  # merged by `rake coverage:check`. Without it workers overwrite each other.
  command_name "RSpec#{ENV['TEST_ENV_NUMBER']}"
  merge_timeout 3600
  enable_coverage :branch
  SimpleCov.skip "/spec/"
  SimpleCov.skip "/harness/"
  SimpleCov.skip "/vendor/"
  SimpleCov.skip "/db/"
  cover "{app,lib}/**/*.rb"
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
