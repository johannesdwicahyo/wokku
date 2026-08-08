# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
# The harness derives AR-encryption keys + secret_key_base from this.
ENV["SECRET_KEY_BASE"] ||= "wokku-test-secret-key-base-000000000000000000000000000000"

require "spec_helper"
# Boot the OSS harness as the test host — it mounts the engine exactly as a
# self-host deployment does (null providers, engine routes auto-drawn).
require_relative "../harness/config/environment"
abort("Rails is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "factory_bot_rails"
require "webmock/rspec"
require "shoulda/matchers"
require "capybara/rspec"

# ActiveJob matchers (have_enqueued_job/mail) need the :test adapter; the
# harness runs :solid_queue in production.
ActiveJob::Base.queue_adapter = :test

WebMock.disable_net_connect!(allow_localhost: true)

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# Load spec support files + factories.
Dir[Rails.root.join("../spec/support/**/*.rb")].sort.each { |f| require f }

# Rack::Attack throttling off in tests (if the host mounts it).
Rack::Attack.enabled = false if defined?(Rack::Attack)

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods

  # ServiceTier has no fixture file; clear any seeded rows so specs that
  # need tiers create their own (mirrors wokku-cloud).
  config.before(:suite) { ServiceTier.delete_all if defined?(ServiceTier) }

  # Rails fixtures provide the baseline data (plans, dyno_tiers, users,
  # teams, servers, ...) the ported specs reference as  etc.
  # FactoryBot coexists for specs that build their own.
  config.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  config.use_transactional_fixtures = true
  config.global_fixtures = :all

  config.include ActiveJob::TestHelper, type: :model
  config.include ActiveJob::TestHelper, type: :job
  config.include ActiveJob::TestHelper, type: :request
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ViewComponent::TestHelpers, type: :component
  config.include ViewComponent::SystemTestHelpers, type: :component  # provides `page`
  config.include Capybara::RSpecMatchers, type: :component
end

# The engine ships factories under spec/factories. factory_bot_rails defaults
# its lookup to Rails.root (the harness dir), so point it at the repo-root
# spec/factories and reload.
FactoryBot.definition_file_paths = [ File.expand_path("factories", __dir__) ]
FactoryBot.reload
