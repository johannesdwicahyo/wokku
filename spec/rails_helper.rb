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

WebMock.disable_net_connect!(allow_localhost: true)

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# Load spec support files + factories.
Dir[Rails.root.join("../spec/support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.fixture_paths = [] # factory_bot only; no fixtures in the OSS suite
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods

  # User#assign_default_plan (and other models) need the baseline product
  # rows. Seed once, committed before the transactional-fixture wrapper, so
  # the rows persist across examples. Idempotent (find_or_create).
  config.before(:suite) do
    Rails.application.load_seed unless Plan.exists?(key: "free")
  end
end

# The engine ships factories under spec/factories. factory_bot_rails defaults
# its lookup to Rails.root (the harness dir), so point it at the repo-root
# spec/factories and reload.
FactoryBot.definition_file_paths = [ File.expand_path("factories", __dir__) ]
FactoryBot.reload
