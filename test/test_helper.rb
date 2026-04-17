require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"
  add_filter "/ee/"
  enable_coverage :branch
  # Target 80% for launch. SimpleCov undercounts due to Zeitwerk autoloading
  # files before Coverage.start — actual coverage is higher than reported.
  minimum_coverage line: 60
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

# Save real methods once at load time so tests can always restore them
NET_SSH_ORIGINAL_START = Net::SSH.method(:start)
NET_HTTP_ORIGINAL_NEW = Net::HTTP.method(:new)
TEMPFILE_ORIGINAL_NEW = Tempfile.method(:new)
DOKKU_APPS_ORIGINAL_CREATE = Dokku::Apps.instance_method(:create) rescue nil
DOKKU_APPS_ORIGINAL_LIST = Dokku::Apps.instance_method(:list) rescue nil
DOKKU_APPS_ORIGINAL_DESTROY = Dokku::Apps.instance_method(:destroy) rescue nil
DOKKU_CONFIG_ORIGINAL_LIST = Dokku::Config.instance_method(:list) rescue nil
DOKKU_CLIENT_ORIGINAL_RUN = Dokku::Client.instance_method(:run) rescue nil
DOKKU_CLIENT_ORIGINAL_CONNECTED = Dokku::Client.instance_method(:connected?) rescue nil
DOKKU_CLIENT_ORIGINAL_RUN_STREAMING = Dokku::Client.instance_method(:run_streaming) rescue nil
DOKKU_PROCESSES_ORIGINAL = {
  restart: (Dokku::Processes.instance_method(:restart) rescue nil),
  stop:    (Dokku::Processes.instance_method(:stop) rescue nil),
  start:   (Dokku::Processes.instance_method(:start) rescue nil),
  scale:   (Dokku::Processes.instance_method(:scale) rescue nil)
}.compact
HETZNER_ORIGINAL_SERVER_STATUS = CloudProviders::Hetzner.instance_method(:server_status) rescue nil
HETZNER_ORIGINAL_INITIALIZE = CloudProviders::Hetzner.instance_method(:initialize) rescue nil

module SshStubHelper
  def stub_net_ssh_start(&block)
    Net::SSH.define_singleton_method(:start, &block)
  end

  def restore_net_ssh_start
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START)
  end

  def stub_dokku_apps_create(&block)
    Dokku::Apps.define_method(:create, &block)
  end

  def restore_dokku_apps
    Dokku::Apps.define_method(:create, DOKKU_APPS_ORIGINAL_CREATE) if DOKKU_APPS_ORIGINAL_CREATE
    Dokku::Apps.define_method(:list, DOKKU_APPS_ORIGINAL_LIST) if DOKKU_APPS_ORIGINAL_LIST
    Dokku::Apps.define_method(:destroy, DOKKU_APPS_ORIGINAL_DESTROY) if DOKKU_APPS_ORIGINAL_DESTROY
  end
end

# Auto-restore after every test class to prevent cross-contamination
module AutoRestoreStubs
  def after_teardown
    super
    I18n.locale = I18n.default_locale
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START)
    Net::HTTP.define_singleton_method(:new, NET_HTTP_ORIGINAL_NEW)
    Tempfile.define_singleton_method(:new, TEMPFILE_ORIGINAL_NEW)
    Dokku::Apps.define_method(:create, DOKKU_APPS_ORIGINAL_CREATE) if DOKKU_APPS_ORIGINAL_CREATE
    Dokku::Apps.define_method(:list, DOKKU_APPS_ORIGINAL_LIST) if DOKKU_APPS_ORIGINAL_LIST
    Dokku::Apps.define_method(:destroy, DOKKU_APPS_ORIGINAL_DESTROY) if DOKKU_APPS_ORIGINAL_DESTROY
    Dokku::Config.define_method(:list, DOKKU_CONFIG_ORIGINAL_LIST) if DOKKU_CONFIG_ORIGINAL_LIST
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
    Dokku::Client.define_method(:connected?, DOKKU_CLIENT_ORIGINAL_CONNECTED) if DOKKU_CLIENT_ORIGINAL_CONNECTED
    Dokku::Client.define_method(:run_streaming, DOKKU_CLIENT_ORIGINAL_RUN_STREAMING) if DOKKU_CLIENT_ORIGINAL_RUN_STREAMING
    DOKKU_PROCESSES_ORIGINAL.each { |name, m| Dokku::Processes.define_method(name, m) }
    CloudProviders::Hetzner.define_method(:server_status, HETZNER_ORIGINAL_SERVER_STATUS) if HETZNER_ORIGINAL_SERVER_STATUS
    CloudProviders::Hetzner.define_method(:initialize, HETZNER_ORIGINAL_INITIALIZE) if HETZNER_ORIGINAL_INITIALIZE
  end
end

ActiveSupport::TestCase.include AutoRestoreStubs
ActionDispatch::IntegrationTest.include AutoRestoreStubs
