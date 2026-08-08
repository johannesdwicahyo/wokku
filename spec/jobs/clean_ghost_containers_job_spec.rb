# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanGhostContainersJob, type: :job do
  DOCKER_PS_OUTPUT = <<~OUTPUT.freeze
    myapp.upcoming-a3f1|4 days ago
    myapp.deploy-b2e9|2 hours ago
    myapp.web.1|3 weeks ago
    otherapp.worker.1|10 minutes ago
    myapp.upcoming-fresh|30 seconds ago
    myapp.deploy-new|45 minutes ago
  OUTPUT

  EXPECTED_REMOVED = %w[myapp.upcoming-a3f1 myapp.deploy-b2e9].freeze

  let(:team)   { create(:team) }
  let(:server) { create(:server, team: team, status: :connected) }

  # Set up a fake SSH session via RSpec stubs that cleanly tears down after
  # each example. The previous Minitest port redefined Net::SSH.start via
  # class_eval and tried to undefine it in an ensure block — but
  # singleton_class.remove_method couldn't actually undo it, and the override
  # leaked into every subsequent spec (docker_health_check + reconcile_app_statuses
  # specs failed for that reason).
  def stub_ssh(docker_ps_output, rm_calls: [])
    fake = Object.new
    fake.define_singleton_method(:exec!) do |cmd|
      if cmd.start_with?("docker ps")
        docker_ps_output
      elsif cmd.start_with?("docker rm -f")
        rm_calls << cmd
        ""
      else
        ""
      end
    end
    allow(Net::SSH).to receive(:start) do |_host, _user, **_opts, &blk|
      blk.call(fake)
    end
    rm_calls
  end

  before { server } # touch let so the server exists before perform_now

  it "removes old ghost containers and ignores non-ghosts and young ghosts" do
    rm_calls = stub_ssh(DOCKER_PS_OUTPUT)
    described_class.perform_now
    expect(rm_calls).not_to be_empty
    EXPECTED_REMOVED.each { |name| expect(rm_calls.join(" ")).to include(name) }
  end

  it "does not call docker rm when no ghosts are found" do
    rm_calls = stub_ssh("myapp.web.1|3 days ago\notherapp.worker.1|2 hours ago\n")
    described_class.perform_now
    expect(rm_calls).to be_empty
  end

  it "skips ghost containers younger than MIN_AGE_HOURS" do
    rm_calls = stub_ssh("myapp.upcoming-young|30 seconds ago\nmyapp.deploy-young|10 minutes ago\n")
    described_class.perform_now
    expect(rm_calls).to be_empty
  end

  it "tolerates SSH failure on one server and continues" do
    # Make the second server fail; the first should still be processed.
    create(:server, name: "flaky-server", host: "10.99.99.99", port: 22,
                    team: team, status: :connected)
    call_count = 0
    fake = Object.new
    fake.define_singleton_method(:exec!) { |_cmd| "" }
    allow(Net::SSH).to receive(:start) do |host, _user, **_opts, &blk|
      call_count += 1
      raise Net::SSH::ConnectionTimeout, "timeout" if host == "10.99.99.99"
      blk.call(fake)
    end

    expect { described_class.perform_now }.not_to raise_error
    expect(call_count).to be >= 2
  end
end
