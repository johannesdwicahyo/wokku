require "test_helper"

class ProvisionServerJobTest < ActiveJob::TestCase
  setup do
    @server = servers(:one)
    # Create a minimal CloudCredential for tests
    @credential = CloudCredential.new(provider: "hetzner", name: "test-cred", team: teams(:one))
    @credential.save(validate: false)
  end

  teardown do
    @credential&.destroy rescue nil
  end

  test "can be enqueued" do
    assert_enqueued_jobs 1 do
      ProvisionServerJob.perform_later(
        server_id: @server.id,
        cloud_credential_id: @credential.id,
        cloud_server_id: "srv-123"
      )
    end
  end

  test "sets server to connected on successful provision" do
    mock_channel = Object.new
    mock_channel.define_singleton_method(:wait) { true }

    mock_ch = Object.new
    mock_ch.define_singleton_method(:on_data) { |&_b| }
    mock_ch.define_singleton_method(:on_extended_data) { |&_b| }
    mock_ch.define_singleton_method(:exec) { |_cmd, &b| b.call(mock_ch, true) }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:exec!) { |_cmd| "" }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_ch); mock_channel }

    CloudProviders::Hetzner.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_cred| }
      define_method(:server_status) { |_id| "running" }
    end

    Net::SSH.class_eval do
      define_singleton_method(:start) { |*_args, **_opts, &block| block.call(mock_ssh) }
    end

    ProvisionServerJob.perform_now(
      server_id: @server.id,
      cloud_credential_id: @credential.id,
      cloud_server_id: "srv-123"
    )

    assert_equal "connected", @server.reload.status
  ensure
    CloudProviders::Hetzner.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :server_status
    end
    Net::SSH.singleton_class.remove_method(:start) rescue nil
  end

  test "sets server to unreachable on failure" do
    CloudProviders::Hetzner.class_eval do
      alias_method :original_initialize, :initialize
      define_method(:initialize) { |_cred| }
      define_method(:server_status) { |_id| raise "API error" }
    end

    ProvisionServerJob.perform_now(
      server_id: @server.id,
      cloud_credential_id: @credential.id,
      cloud_server_id: "srv-123"
    )

    assert_equal "unreachable", @server.reload.status
  ensure
    CloudProviders::Hetzner.class_eval do
      alias_method :initialize, :original_initialize
      remove_method :original_initialize
      remove_method :server_status
    end
  end
end
