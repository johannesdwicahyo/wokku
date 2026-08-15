# frozen_string_literal: true

require "rails_helper"

RSpec.describe TerminalSession do
  let(:server) { servers(:one) }

  # Save Net::SSH.start at file load time so we can restore between tests
  NET_SSH_ORIGINAL_START_FOR_SPEC = Net::SSH.method(:start) unless defined?(NET_SSH_ORIGINAL_START_FOR_SPEC)

  describe "Swarm-leg sessions (B6 W4)" do
    def swarm_ssh(container: "wokku-swarmy-web.1.abc123", shell_probe: "bash")
      mock_ssh = Object.new
      mock_ssh.define_singleton_method(:closed?) { false }
      mock_ssh.define_singleton_method(:close) { }
      mock_ssh.define_singleton_method(:exec!) do |cmd|
        cmd.include?("docker ps") ? "other.web.1\n#{container}\n" : shell_probe
      end
      mock_ssh.define_singleton_method(:open_channel) { |&_b| raise "channel-mock-stop" }
      mock_ssh
    end

    def stub_ssh(mock_ssh, &on_start)
      Net::SSH.define_singleton_method(:start) do |*args, **_opts|
        on_start&.call(args[1])
        mock_ssh
      end
    end

    around do |ex|
      ex.run
    ensure
      Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START_FOR_SPEC)
    end

    let!(:app) do
      create(:app_record, server: server, name: "swarmy", wokkud_lifecycle: true)
    end

    it "enter connects as root and docker-execs into the live task container" do
      users_seen = []
      mock = swarm_ssh
      stub_ssh(mock) { |u| users_seen << u }

      session = described_class.new(server: server, mode: :enter, target: "swarmy")
      session.connect! rescue nil # channel mock is minimal; command is what we assert

      expect(users_seen).to eq([ "root" ])
      expect(session.send(:build_command)).to eq("docker exec -it wokku-swarmy-web.1.abc123 /bin/bash")
    end

    it "enter honors the sh-only probe" do
      mock = swarm_ssh(shell_probe: "sh")
      stub_ssh(mock)

      session = described_class.new(server: server, mode: :enter, target: "swarmy")
      session.connect! rescue nil

      expect(session.send(:build_command)).to eq("docker exec -it wokku-swarmy-web.1.abc123 /bin/sh")
    end

    it "exec runs argv inside the running task container" do
      mock = swarm_ssh
      stub_ssh(mock)

      session = described_class.new(server: server, mode: :exec, target: "swarmy", argv: [ "rails", "db:migrate" ])
      session.connect! rescue nil

      expect(session.send(:build_command)).to eq("docker exec -i wokku-swarmy-web.1.abc123 rails db:migrate")
    end

    it "raises a clear error when no task container is running" do
      mock = swarm_ssh(container: "unrelated.web.1")
      stub_ssh(mock)

      session = described_class.new(server: server, mode: :enter, target: "swarmy")
      expect { session.connect! }.to raise_error(/No running task for swarmy/)
    end

    it "keeps legacy apps on the dokku user and dokku enter" do
      app.update!(wokkud_lifecycle: false)
      users_seen = []
      mock = swarm_ssh
      stub_ssh(mock) { |u| users_seen << u }

      session = described_class.new(server: server, mode: :enter, target: "swarmy")
      session.connect! rescue nil

      expect(users_seen).to eq([ server.ssh_user || "dokku" ])
      expect(session.send(:build_command)).to start_with("enter swarmy web")
    end
  end

  it "initializes with server" do
    session = described_class.new(server: server)
    expect(session.server).to eq(server)
    expect(session.connected?).to be_falsey
  end

  it "builds ssh options from server" do
    session = described_class.new(server: server)
    opts = session.send(:ssh_options)
    expect(opts[:port]).to eq(server.port)
    expect(opts[:non_interactive]).to be_truthy
  end

  it "ssh_options includes key_data when server has private key" do
    server.ssh_private_key = "-----BEGIN RSA PRIVATE KEY-----\nfakekey\n-----END RSA PRIVATE KEY-----"
    session = described_class.new(server: server)
    opts = session.send(:ssh_options)
    expect(opts[:key_data]).to be_present
    expect(opts[:key_data]).to include(server.ssh_private_key)
  ensure
    server.ssh_private_key = nil
  end

  it "ssh_options does not include key_data when server has no private key" do
    server.ssh_private_key = nil
    session = described_class.new(server: server)
    opts = session.send(:ssh_options)
    expect(opts.key?(:key_data)).to be_falsey
  end

  it "tracks last activity for timeout" do
    session = described_class.new(server: server)
    session.touch!
    expect(session.last_activity_at.to_f).to be_within(1.0).of(Time.current.to_f)
  end

  it "timed_out? returns true after inactivity" do
    session = described_class.new(server: server, timeout: 1.second)
    session.touch!
    sleep 1.1
    expect(session.timed_out?).to be_truthy
  end

  it "timed_out? returns false when recently active" do
    session = described_class.new(server: server, timeout: 10.minutes)
    session.touch!
    expect(session.timed_out?).to be_falsey
  end

  it "connect! opens SSH connection for server shell" do
    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }
    mock_channel.define_singleton_method(:request_pty) { |**_opts, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:send_channel_request) { |_type, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:on_data) { |&_b| }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }
    mock_channel.define_singleton_method(:on_request) { |_type, &_b| }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_channel); mock_channel }
    mock_ssh.define_singleton_method(:close) { }

    Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_block| mock_ssh }

    session = described_class.new(server: server)
    expect { session.connect! }.not_to raise_error
  ensure
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START_FOR_SPEC)
  end

  it "connect! opens SSH connection for app console" do
    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }
    mock_channel.define_singleton_method(:request_pty) { |**_opts, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:exec) { |_cmd, &b| b.call(nil, true) }
    mock_channel.define_singleton_method(:on_data) { |&_b| }
    mock_channel.define_singleton_method(:on_extended_data) { |&_b| }
    mock_channel.define_singleton_method(:on_request) { |_type, &_b| }

    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:open_channel) { |&b| b.call(mock_channel); mock_channel }
    mock_ssh.define_singleton_method(:close) { }

    Net::SSH.define_singleton_method(:start) { |*_args, **_opts, &_block| mock_ssh }

    session = described_class.new(server: server, app_name: "my-app")
    expect { session.connect! }.not_to raise_error
  ensure
    Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START_FOR_SPEC)
  end

  it "disconnect! closes channel and SSH connection" do
    mock_channel = Object.new
    close_called = false
    mock_channel.define_singleton_method(:close) { close_called = true }

    mock_ssh = Object.new
    ssh_close_called = false
    mock_ssh.define_singleton_method(:close) { ssh_close_called = true }

    session = described_class.new(server: server)
    session.instance_variable_set(:@channel, mock_channel)
    session.instance_variable_set(:@ssh, mock_ssh)

    session.disconnect!

    expect(close_called).to be_truthy
    expect(ssh_close_called).to be_truthy
    expect(session.instance_variable_get(:@ssh)).to be_nil
    expect(session.instance_variable_get(:@channel)).to be_nil
  end

  it "connected? returns false when ssh is nil" do
    session = described_class.new(server: server)
    expect(session.connected?).to be_falsey
  end

  it "connected? returns false when ssh is closed" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { true }

    mock_channel = Object.new
    mock_channel.define_singleton_method(:active?) { true }

    session = described_class.new(server: server)
    session.instance_variable_set(:@ssh, mock_ssh)
    session.instance_variable_set(:@channel, mock_channel)

    expect(session.connected?).to be_falsey
  end

  it "send_data does nothing when not connected" do
    session = described_class.new(server: server)
    expect { session.send_data("some command\n") }.not_to raise_error
  end

  it "resize does nothing when channel is nil" do
    session = described_class.new(server: server)
    expect { session.resize(120, 30) }.not_to raise_error
  end

  it "process does nothing when ssh is nil" do
    session = described_class.new(server: server)
    expect { session.process }.not_to raise_error
  end

  it "process handles IOError gracefully" do
    mock_ssh = Object.new
    mock_ssh.define_singleton_method(:closed?) { false }
    mock_ssh.define_singleton_method(:process) { |_t| raise IOError, "stream closed" }
    mock_ssh.define_singleton_method(:close) { }

    mock_channel = Object.new
    mock_channel.define_singleton_method(:close) { }

    session = described_class.new(server: server)
    session.instance_variable_set(:@ssh, mock_ssh)
    session.instance_variable_set(:@channel, mock_channel)

    expect { session.process }.not_to raise_error
  end

  # --- Mode / build_command tests ---

  it "default mode is :shell when not specified (backward compat)" do
    s = described_class.new(server: server)
    expect(s.mode).to eq(:shell)
  end

  it "app_name kwarg sets mode :enter (deprecated backward-compat alias)" do
    s = described_class.new(server: server, app_name: "x")
    expect(s.mode).to eq(:enter)
  end

  it "build_command for mode :enter assembles dokku enter <app> web without a shell wrapper" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    cmd = s.send(:build_command)
    expect(cmd).to eq("enter myapp web")
    expect(cmd).not_to include("/bin/sh")
    expect(cmd).not_to include("-lc")
  end

  it "build_command for mode :enter appends /bin/sh when probe detected sh-only" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    s.instance_variable_set(:@shell_binary, :sh)
    expect(s.send(:build_command)).to eq("enter myapp web /bin/sh")
  end

  it "build_command for mode :enter falls back to bash-default when probe detected bash" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    s.instance_variable_set(:@shell_binary, :bash)
    expect(s.send(:build_command)).to eq("enter myapp web")
  end

  describe "#probe_shell!" do
    let(:s) { described_class.new(server: server, mode: :enter, target: "myapp") }
    let(:ssh) { instance_double(Net::SSH::Connection::Session) }

    before do
      s.instance_variable_set(:@ssh, ssh)
      Rails.cache.delete("terminal_shell:#{server.id}:myapp")
    end

    it "sets @shell_binary = :sh when probe output is 'sh'" do
      expect(ssh).to receive(:exec!).and_return("sh\n")
      s.send(:probe_shell!)
      expect(s.instance_variable_get(:@shell_binary)).to eq(:sh)
    end

    it "sets @shell_binary = :bash when probe output is 'bash'" do
      expect(ssh).to receive(:exec!).and_return("bash\n")
      s.send(:probe_shell!)
      expect(s.instance_variable_get(:@shell_binary)).to eq(:bash)
    end

    it "defaults to :bash on any probe failure (fail-open)" do
      expect(ssh).to receive(:exec!).and_raise(IOError.new("connection lost"))
      s.send(:probe_shell!)
      expect(s.instance_variable_get(:@shell_binary)).to eq(:bash)
    end

    it "uses the documented dokku-enter probe command (no PTY so no stdout-loss)" do
      expect(ssh).to receive(:exec!).with(
        a_string_matching(%r{\Aenter myapp web -- /bin/sh -c }) &
        a_string_including("test").and(including("/bin/bash"))
      ).and_return("bash")
      s.send(:probe_shell!)
    end

    context "with a real cache store (overrides test env's null_store)" do
      around do |example|
        original = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        example.run
        Rails.cache = original
      end

      it "caches the probe result for subsequent calls (no SSH on cache hit)" do
        expect(ssh).to receive(:exec!).once.and_return("sh")
        s.send(:probe_shell!) # miss → SSH probe + cache write
        expect(s.instance_variable_get(:@shell_binary)).to eq(:sh)

        # New session against the same server+target → hit cache
        s2 = described_class.new(server: server, mode: :enter, target: "myapp")
        s2.instance_variable_set(:@ssh, ssh)
        s2.send(:probe_shell!)
        expect(s2.instance_variable_get(:@shell_binary)).to eq(:sh)
      end

      it "does NOT cache failures (next attempt re-probes)" do
        expect(ssh).to receive(:exec!).twice.and_raise(IOError.new("network blip"))
        s.send(:probe_shell!)
        expect(s.instance_variable_get(:@shell_binary)).to eq(:bash) # fail-open

        s2 = described_class.new(server: server, mode: :enter, target: "myapp")
        s2.instance_variable_set(:@ssh, ssh)
        s2.send(:probe_shell!) # cache miss, re-probes (second exec!)
      end
    end
  end

  it "build_command for mode :enter escapes app name with spaces" do
    s = described_class.new(server: server, mode: :enter, target: "my app")
    cmd = s.send(:build_command)
    expect(cmd).not_to include("my app")  # raw unescaped name must not appear
    expect(cmd.start_with?("enter ")).to be_truthy
    expect(cmd.end_with?(" web")).to be_truthy
  end

  it "build_command for mode :exec uses dokku run with argv args individually escaped" do
    s = described_class.new(server: server, mode: :exec, target: "myapp",
                            argv: [ "bundle", "exec", "rake", "db:migrate" ])
    cmd = s.send(:build_command)
    expect(cmd.start_with?("run myapp ")).to be_truthy
    expect(cmd).to include("bundle")
    expect(cmd).to include("db:migrate")
    expect(cmd).not_to include("/bin/sh")
  end

  it "build_command for mode :exec escapes argv values containing shell metacharacters" do
    s = described_class.new(server: server, mode: :exec, target: "myapp",
                            argv: [ "echo", "hello; rm -rf /" ])
    cmd = s.send(:build_command)
    expect(cmd).not_to match(%r{; rm -rf /})
    expect(cmd).to include("echo")
  end

  it "build_command for mode :exec safely escapes argv containing single quotes" do
    s = described_class.new(server: server, mode: :exec, target: "myapp",
                            argv: [ "echo", "it's broken; rm -rf /" ])
    cmd = s.send(:build_command)
    expect(cmd).not_to match(%r{; rm -rf /})
    expect(cmd.start_with?("run myapp ")).to be_truthy
  end

  describe "db_connect (docker exec — W7)" do
    let(:server) { create(:server) }

    def stub_ssh(mock_ssh, &on_start)
      Net::SSH.define_singleton_method(:start) do |*args, **_opts|
        on_start&.call(args[1])
        mock_ssh
      end
    end

    around do |ex|
      ex.run
    ensure
      Net::SSH.define_singleton_method(:start, NET_SSH_ORIGINAL_START_FOR_SPEC)
    end

    def session_for(db, db_kind: nil)
      s = described_class.new(server: server, mode: :db_connect, target: db.name, db_kind: db_kind)
      s.instance_variable_set(:@db_service, db)
      s.instance_variable_set(:@db_container, db.container_name)
      s
    end

    it "builds psql for a dedicated postgres" do
      db = create(:database_service, server: server, service_type: "postgres", name: "kb-bot-db",
                  dsn: "postgres://postgres:pw@dokku.postgres.kb-bot-db:5432/kb_bot_db")
      expect(session_for(db).send(:build_command))
        .to eq("docker exec -it dokku.postgres.kb-bot-db psql -U postgres -d kb_bot_db")
    end

    it "raises for a shared tenant BEFORE any docker ps exec (no root session in the shared parent)" do
      parent = create(:database_service, server: server, service_type: "postgres",
                      name: "dokku-shared-postgres", tier_name: "shared_host")
      tenant = create(:database_service, server: server, service_type: "postgres", name: "app-pg-shared-abc123",
                      tier_name: "shared_free", shared: true, parent_service: parent, shared_db_name: "app_tenant")

      mock_ssh = Object.new
      mock_ssh.define_singleton_method(:closed?) { false }
      mock_ssh.define_singleton_method(:close) { }
      mock_ssh.define_singleton_method(:exec!) { |cmd| raise "docker ps must never run for a shared row: #{cmd}" }
      stub_ssh(mock_ssh)

      session = described_class.new(server: server, mode: :db_connect, target: tenant.name)
      expect { session.connect! }
        .to raise_error(ArgumentError, /shared-tenant console is not yet supported/)
    end

    it "builds mariadb with MYSQL_PWD outside the container argv" do
      db = create(:database_service, server: server, service_type: "mariadb", name: "ghost-mysql",
                  dsn: "mysql://root:s3cret@dokku.mariadb.ghost-mysql:3306/ghost_mysql")
      cmd = session_for(db).send(:build_command)
      expect(cmd).to include("-e MYSQL_PWD=s3cret")
      expect(cmd).to match(/mariadb -uroot ghost_mysql\z/)
    end

    it "builds redis-cli with -a only when the DSN has a password" do
      with_pw = create(:database_service, server: server, service_type: "redis", name: "r1",
                       dsn: "redis://:tok@dokku.redis.r1:6379")
      without = create(:database_service, server: server, service_type: "redis", name: "r2", dsn: nil)
      expect(session_for(with_pw).send(:build_command)).to include("redis-cli --no-auth-warning -a tok")
      expect(session_for(without).send(:build_command)).to match(/redis-cli\z/)
    end

    it "escapes hostile database names" do
      db = create(:database_service, server: server, service_type: "postgres", name: "x",
                  dsn: nil)
      allow(db).to receive(:dedicated_db_name).and_return("evil; rm -rf /")
      expect(session_for(db).send(:build_command)).to include(Shellwords.escape("evil; rm -rf /"))
    end

    it "rejects a db_kind mismatch" do
      db = create(:database_service, server: server, service_type: "postgres", name: "pgx", dsn: nil)
      expect { session_for(db, db_kind: "redis").send(:validate_db_kind!) }
        .to raise_error(ArgumentError, /db_kind mismatch/)
    end

    it "raises for engines with no interactive client" do
      db = create(:database_service, server: server, service_type: "memcached", name: "mc", dsn: nil)
      expect { session_for(db).send(:build_command) }
        .to raise_error(ArgumentError, /no interactive client/)
    end

    it "raises a clear error when no DatabaseService row matches target+server" do
      mock_ssh = Object.new
      mock_ssh.define_singleton_method(:closed?) { false }
      mock_ssh.define_singleton_method(:close) { }
      stub_ssh(mock_ssh)

      session = described_class.new(server: server, mode: :db_connect, target: "nonexistent-db")
      expect { session.connect! }
        .to raise_error(/Unknown database/)
    end

    it "raises when the database row exists but its container is absent from docker ps output" do
      db = create(:database_service, server: server, service_type: "postgres", name: "kb-bot-db")

      mock_ssh = Object.new
      mock_ssh.define_singleton_method(:closed?) { false }
      mock_ssh.define_singleton_method(:close) { }
      mock_ssh.define_singleton_method(:exec!) do |cmd|
        cmd.include?("docker ps") ? "some-other-container\nanother-container\n" : "bash"
      end
      stub_ssh(mock_ssh)

      session = described_class.new(server: server, mode: :db_connect, target: db.name)
      expect { session.connect! }
        .to raise_error(/is not running/)
    end

    it "performs exact-name matching: rejects superstring container names" do
      # Container name is "dokku.postgres.kb-bot-db"; docker ps returns a superstring
      db = create(:database_service, server: server, service_type: "postgres", name: "kb-bot-db")

      mock_ssh = Object.new
      mock_ssh.define_singleton_method(:closed?) { false }
      mock_ssh.define_singleton_method(:close) { }
      mock_ssh.define_singleton_method(:exec!) do |cmd|
        # Return a superstring that would match with substring/regex search
        cmd.include?("docker ps") ? "dokku.postgres.kb-bot-dbx\n" : "bash"
      end
      stub_ssh(mock_ssh)

      session = described_class.new(server: server, mode: :db_connect, target: db.name)
      expect { session.connect! }
        .to raise_error(/is not running/)
    end
  end

  it "rejects unknown mode at construction time" do
    expect {
      described_class.new(server: server, mode: :evil, target: "x")
    }.to raise_error(ArgumentError)
  end

  it "requires target for non-shell modes" do
    expect {
      described_class.new(server: server, mode: :enter, target: nil)
    }.to raise_error(ArgumentError)
  end

  it "exec mode with empty argv raises when build_command runs" do
    s = described_class.new(server: server, mode: :exec, target: "myapp", argv: [])
    expect { s.send(:build_command) }.to raise_error(ArgumentError)
  end

  it "on_exit registers a callback that captures exit_code" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    captured = nil
    s.on_exit { |code| captured = code }
    s.instance_variable_get(:@on_exit).call(42)
    expect(captured).to eq(42)
  end

  it "exit_code is nil before any SSH exit-status received" do
    s = described_class.new(server: server, mode: :enter, target: "myapp")
    expect(s.exit_code).to be_nil
  end

  describe "session plumbing (coverage)" do
    let(:server) { servers(:one) }

    it "rejects app_name: combined with an explicit mode" do
      expect {
        described_class.new(server: server, mode: :enter, target: "x", app_name: "x")
      }.to raise_error(ArgumentError, /deprecated/)
    end

    it "connected? is false when the ssh handle raises" do
      session = described_class.new(server: server)
      broken = Object.new
      broken.define_singleton_method(:closed?) { raise IOError, "gone" }
      session.instance_variable_set(:@ssh, broken)
      expect(session.connected?).to be(false)
    end

    it "send_data touches activity and forwards to the channel" do
      session = described_class.new(server: server)
      ssh = Object.new
      ssh.define_singleton_method(:closed?) { false }
      sent = []
      channel = Object.new
      channel.define_singleton_method(:active?) { true }
      channel.define_singleton_method(:send_data) { |d| sent << d }
      session.instance_variable_set(:@ssh, ssh)
      session.instance_variable_set(:@channel, channel)
      before = session.last_activity_at
      session.send_data("ls\n")
      expect(sent).to eq([ "ls\n" ])
      expect(session.last_activity_at).to be >= before if before
    end

    it "on_output wires stdout and stderr callbacks" do
      session = described_class.new(server: server)
      handlers = {}
      channel = Object.new
      channel.define_singleton_method(:on_data) { |&b| handlers[:out] = b }
      channel.define_singleton_method(:on_extended_data) { |&b| handlers[:err] = b }
      session.instance_variable_set(:@channel, channel)
      seen = []
      session.on_output { |d| seen << d }
      handlers[:out].call(nil, "o")
      handlers[:err].call(nil, 1, "e")
      expect(seen).to eq(%w[o e])
    end

    it "resize sends a window-change request and swallows errors" do
      session = described_class.new(server: server)
      reqs = []
      channel = Object.new
      channel.define_singleton_method(:send_channel_request) { |*a| reqs << a }
      session.instance_variable_set(:@channel, channel)
      session.resize(80, 24)
      expect(reqs.first.first).to eq("window-change")

      raising = Object.new
      raising.define_singleton_method(:send_channel_request) { |*| raise IOError, "closed" }
      session.instance_variable_set(:@channel, raising)
      expect { session.resize(80, 24) }.not_to raise_error
    end

    it "build_command raises for an unimplemented mode" do
      session = described_class.new(server: server)
      session.instance_variable_set(:@mode, :bogus)
      expect { session.send(:build_command) }
        .to raise_error(ArgumentError, /not implemented/)
    end
  end
end
