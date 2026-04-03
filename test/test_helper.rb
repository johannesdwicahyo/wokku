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

# Save real methods once at load time so tests can always restore them
NET_SSH_ORIGINAL_START = Net::SSH.method(:start)
NET_HTTP_ORIGINAL_NEW = Net::HTTP.method(:new)
TEMPFILE_ORIGINAL_NEW = Tempfile.method(:new)
DOKKU_APPS_ORIGINAL_CREATE = Dokku::Apps.instance_method(:create) rescue nil
DOKKU_APPS_ORIGINAL_LIST = Dokku::Apps.instance_method(:list) rescue nil
DOKKU_APPS_ORIGINAL_DESTROY = Dokku::Apps.instance_method(:destroy) rescue nil
DOKKU_CONFIG_ORIGINAL_LIST = Dokku::Config.instance_method(:list) rescue nil
DOKKU_CLIENT_ORIGINAL_RUN = Dokku::Client.instance_method(:run) rescue nil

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
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START)
    Net::HTTP.define_singleton_method(:new, NET_HTTP_ORIGINAL_NEW)
    Tempfile.define_singleton_method(:new, TEMPFILE_ORIGINAL_NEW)
    Dokku::Apps.define_method(:create, DOKKU_APPS_ORIGINAL_CREATE) if DOKKU_APPS_ORIGINAL_CREATE
    Dokku::Apps.define_method(:list, DOKKU_APPS_ORIGINAL_LIST) if DOKKU_APPS_ORIGINAL_LIST
    Dokku::Apps.define_method(:destroy, DOKKU_APPS_ORIGINAL_DESTROY) if DOKKU_APPS_ORIGINAL_DESTROY
    Dokku::Config.define_method(:list, DOKKU_CONFIG_ORIGINAL_LIST) if DOKKU_CONFIG_ORIGINAL_LIST
    Dokku::Client.define_method(:run, DOKKU_CLIENT_ORIGINAL_RUN) if DOKKU_CLIENT_ORIGINAL_RUN
  end
end

ActiveSupport::TestCase.include AutoRestoreStubs
ActionDispatch::IntegrationTest.include AutoRestoreStubs
