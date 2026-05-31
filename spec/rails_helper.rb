# frozen_string_literal: true

# SimpleCov FIRST — must start before any application code loads.
# command_name "RSpec" lets it merge with the Minitest run (which uses
# command_name "Minitest"). The merged report is what the coverage gate
# checks.
require "simplecov"
SimpleCov.start "rails" do
  command_name "RSpec"
  add_filter "/test/"
  add_filter "/spec/"
  add_filter "/config/"
  add_filter "/vendor/"
  enable_coverage :branch
  minimum_coverage line: 88
end

require "webmock/rspec"
WebMock.disable_net_connect!(allow_localhost: true)

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"

# Match test/test_helper.rb: integration test-only env vars. Real values
# live in .kamal/secrets in production.
ENV["IPAYMU_VA"]      ||= "TEST_VA"
ENV["IPAYMU_API_KEY"] ||= "TEST_API_KEY"
ENV["IPAYMU_URL"]     ||= "https://sandbox.ipaymu.com"

require_relative "../config/environment"
abort("Rails is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "factory_bot_rails"

# Auto-load any spec/support/**/*.rb helpers.
Dir[Rails.root.join("spec/support/**/*.rb")].each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Disable Rack::Attack throttling in tests to avoid rate limit interference.
Rack::Attack.enabled = false

RSpec.configure do |config|
  # Use the existing Rails fixtures for parity with Minitest during the
  # strangler-fig migration. New specs may also use FactoryBot via
  # `create(:user, ...)` — both work side-by-side.
  config.fixture_paths = [ Rails.root.join("test/fixtures") ]
  config.use_transactional_fixtures = true
  config.global_fixtures = :all

  # FactoryBot: include short syntax (`build`, `create`, etc.) so specs
  # don't need to qualify with `FactoryBot.`.
  config.include FactoryBot::Syntax::Methods

  # ActiveJob + TimeHelpers for model, job, and request specs.
  config.include ActiveJob::TestHelper, type: :model
  config.include ActiveJob::TestHelper, type: :job
  config.include ActiveJob::TestHelper, type: :request
  config.include ActiveSupport::Testing::TimeHelpers

  # ViewComponent: render_inline + Capybara matchers in spec/components/**
  config.include ViewComponent::TestHelpers,     type: :component
  config.include ViewComponent::SystemTestHelpers, type: :component
  config.include Capybara::RSpecMatchers,        type: :component

  # Filter Rails noise from backtraces.
  config.filter_rails_from_backtrace!

  # Infer spec type from file location (spec/models → :model, etc.).
  config.infer_spec_type_from_file_location!
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
