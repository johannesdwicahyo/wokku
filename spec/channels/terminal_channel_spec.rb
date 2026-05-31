require "rails_helper"

RSpec.describe TerminalChannel, type: :channel do
  # FakeTerminalSession -- no real SSH; used by tests that need a live session.
  class FakeTerminalSession
    attr_reader :mode, :target, :argv, :db_kind

    def initialize(server:, mode: :shell, target: nil, argv: [], db_kind: nil, **_opts)
      @server    = server
      @mode      = mode
      @target    = target
      @argv      = argv
      @db_kind   = db_kind
      @live      = true
      @on_output = nil
      @on_exit   = nil
    end

    def connect!; self; end
    def connected?; @live; end
    def disconnect!; @live = false; end
    def on_output(&block); @on_output = block; end
    def on_exit(&block); @on_exit = block; end
    def send_data(_data); end
    def resize(_cols, _rows); end
    # Honor the timeout so the channel's process_loop doesn't busy-spin
    # across examples (each `start` spawns a background thread that runs
    # until @live = false).
    def process(timeout = 0.01); sleep(timeout); end
    def timed_out?; false; end

    def simulate_output(bytes); @on_output&.call(bytes); end
    def simulate_exit(code); @on_exit&.call(code); end
  end

  # Track fake sessions so we can mark them disconnected after each example.
  # The channel's process_loop thread otherwise busy-spins on a still-"connected?"
  # fake and accumulates across examples.
  let(:fake_sessions) { [] }

  after do
    fake_sessions.each { |f| f.disconnect! rescue nil }
  end

  def with_fake_session(fake)
    fake_sessions << fake
    allow(TerminalSession).to receive(:new).and_return(fake)
    yield
  end

  def with_capturing_session
    captured = nil
    allow(TerminalSession).to receive(:new) do |**kwargs|
      captured = kwargs
      fake = FakeTerminalSession.new(**kwargs)
      fake_sessions << fake
      fake
    end
    yield
    captured
  end

  def stream_name_for(sub)
    sub.streams.first
  end

  def send_message(data)
    subscription.perform_action(data.stringify_keys)
  end

  # ---------------------------------------------------------------------------
  # Subscription ACL
  # ---------------------------------------------------------------------------

  describe "subscription ACL" do
    it "rejects without server_id" do
      stub_connection current_user: users(:one)
      subscribe
      expect(subscription).to be_rejected
    end

    it "rejects for a nonexistent server_id" do
      stub_connection current_user: users(:one)
      subscribe server_id: "00000000-0000-0000-0000-000000000000"
      expect(subscription).to be_rejected
    end

    it "accepts for a server in the user's team" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:one).id
      expect(subscription).to be_confirmed
      expect(subscription.streams.length).to eq(1)
    end

    it "accepts for a server in a different team (ACL deferred to handle_start)" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:two).id
      expect(subscription).to be_confirmed
    end

    it "subscribes for an app on a server in a different team (multi-tenant case)" do
      cross_team_app = app_records(:cross_team)
      stub_connection current_user: users(:one)
      subscribe(server_id: cross_team_app.server_id)
      expect(subscription).to be_confirmed
    end
  end

  describe "start mode enter cross-team" do
    it "resolves app via policy_scope across teams" do
      cross_team_app = app_records(:cross_team)
      stub_connection current_user: users(:one)
      fake = FakeTerminalSession.new(server: servers(:two), mode: :enter, target: cross_team_app.name)

      with_fake_session(fake) do
        subscribe(server_id: cross_team_app.server_id)
        expect(subscription).to be_confirmed

        stream = stream_name_for(subscription)
        expect {
          send_message(
            "type" => "start", "mode" => "enter",
            "target" => cross_team_app.name, "argv" => []
          )
        }.to have_broadcasted_to(stream).with(hash_including(type: "ready"))
      end
    end
  end

  describe "start with unknown mode" do
    it "broadcasts error" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:one).id
      stream = stream_name_for(subscription)

      expect {
        send_message("type" => "start", "mode" => "bogus", "target" => nil, "argv" => [])
      }.to have_broadcasted_to(stream).with(hash_including(type: "error", message: "unknown mode"))
    end
  end

  describe "start mode shell" do
    it "denies for non-admin team member" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:one).id
      stream = stream_name_for(subscription)

      expect {
        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])
      }.to have_broadcasted_to(stream).with(hash_including(type: "error", message: "shell mode requires admin role"))
    end

    it "broadcasts ready for admin" do
      stub_connection current_user: users(:admin)
      fake = FakeTerminalSession.new(server: servers(:one))

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        stream = stream_name_for(subscription)

        expect {
          send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])
        }.to have_broadcasted_to(stream).with(hash_including(type: "ready"))
      end
    end
  end

  describe "start mode enter" do
    it "broadcasts error with empty target" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:one).id
      stream = stream_name_for(subscription)

      expect {
        send_message("type" => "start", "mode" => "enter", "target" => "", "argv" => [])
      }.to have_broadcasted_to(stream).with(hash_including(type: "error", message: "target required"))
    end

    it "broadcasts access-denied error for an app in another team" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:one).id
      stream = stream_name_for(subscription)

      expect {
        send_message(
          "type" => "start", "mode" => "enter",
          "target" => app_records(:two).name, "argv" => []
        )
      }.to have_broadcasted_to(stream).with(hash_including(type: "error", message: "app not found or access denied"))
    end

    it "broadcasts ready with an accessible app" do
      stub_connection current_user: users(:one)
      app  = app_records(:one)
      fake = FakeTerminalSession.new(server: servers(:one), mode: :enter, target: app.name)

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        stream = stream_name_for(subscription)

        expect {
          send_message("type" => "start", "mode" => "enter", "target" => app.name, "argv" => [])
        }.to have_broadcasted_to(stream).with(hash_including(type: "ready"))
      end
    end
  end

  describe "start mode db_connect" do
    it "broadcasts error with empty target" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:one).id
      stream = stream_name_for(subscription)

      expect {
        send_message("type" => "start", "mode" => "db_connect", "target" => "", "argv" => [])
      }.to have_broadcasted_to(stream).with(hash_including(type: "error", message: "target required"))
    end

    it "broadcasts access-denied error for a database in another team" do
      stub_connection current_user: users(:one)
      subscribe server_id: servers(:one).id
      stream = stream_name_for(subscription)

      expect {
        send_message(
          "type" => "start", "mode" => "db_connect",
          "target" => database_services(:two).name, "argv" => []
        )
      }.to have_broadcasted_to(stream).with(hash_including(type: "error", message: "database not found or access denied"))
    end

    it "broadcasts ready with an accessible database" do
      stub_connection current_user: users(:one)
      db   = database_services(:one)
      fake = FakeTerminalSession.new(server: servers(:one), mode: :db_connect, target: db.name, db_kind: db.service_type)

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        stream = stream_name_for(subscription)

        expect {
          send_message("type" => "start", "mode" => "db_connect", "target" => db.name, "argv" => [])
        }.to have_broadcasted_to(stream).with(hash_including(type: "ready"))
      end
    end
  end

  describe "double-start guard" do
    it "broadcasts already-started on the second call" do
      stub_connection current_user: users(:admin)
      fake = FakeTerminalSession.new(server: servers(:one))

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        stream = stream_name_for(subscription)

        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])

        expect {
          send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])
        }.to have_broadcasted_to(stream).with(hash_including(type: "error", message: "already started"))
      end
    end
  end

  describe "start mode exec" do
    it "broadcasts ready" do
      stub_connection current_user: users(:one)
      app  = app_records(:one)
      fake = FakeTerminalSession.new(server: servers(:one), mode: :exec, target: app.name, argv: [ "bundle", "exec", "rake" ])

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        stream = stream_name_for(subscription)

        expect {
          send_message("type" => "start", "mode" => "exec", "target" => app.name, "argv" => [ "bundle", "exec", "rake" ])
        }.to have_broadcasted_to(stream).with(hash_including(type: "ready"))
      end
    end

    it "passes mode :exec with correct argv to TerminalSession.new" do
      stub_connection current_user: users(:one)
      app = app_records(:one)

      captured = with_capturing_session do
        subscribe server_id: servers(:one).id
        send_message("type" => "start", "mode" => "exec", "target" => app.name, "argv" => [ "bundle", "exec", "rake" ])
      end

      expect(captured).not_to be_nil
      expect(captured[:mode]).to eq(:exec)
      expect(captured[:target]).to eq(app.name)
      expect(captured[:argv]).to eq([ "bundle", "exec", "rake" ])
    end
  end

  describe "resize handler" do
    it "calls session.resize with cols and rows" do
      stub_connection current_user: users(:admin)

      resized_with = nil
      fake = FakeTerminalSession.new(server: servers(:one))
      fake.define_singleton_method(:resize) { |cols, rows| resized_with = [ cols, rows ] }

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])
        send_message("type" => "resize", "cols" => 100, "rows" => 50)
      end

      expect(resized_with).to eq([ 100, 50 ])
    end
  end

  describe "signal handler" do
    it "sends Ctrl-C byte for INT" do
      stub_connection current_user: users(:admin)

      sent_data = []
      fake = FakeTerminalSession.new(server: servers(:one))
      fake.define_singleton_method(:send_data) { |data| sent_data << data }

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])
        send_message("type" => "signal", "signal" => "INT")
      end

      expect(sent_data).to include("\x03")
    end

    it "sends no byte for TERM" do
      stub_connection current_user: users(:admin)

      sent_data = []
      fake = FakeTerminalSession.new(server: servers(:one))
      fake.define_singleton_method(:send_data) { |data| sent_data << data }

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])
        send_message("type" => "signal", "signal" => "TERM")
      end

      expect(sent_data).to be_empty
    end
  end

  describe "Activity.log on successful start" do
    it "invokes Activity.log with terminal.start and mode" do
      stub_connection current_user: users(:admin)
      fake = FakeTerminalSession.new(server: servers(:one))

      logged = []
      allow(Activity).to receive(:log) { |**kwargs| logged << kwargs }

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])
      end

      expect(logged.size).to eq(1)
      expect(logged.first[:action]).to eq("terminal.start")
      expect(logged.first[:metadata][:mode]).to eq("shell")
    end
  end

  describe "exit propagation" do
    it "propagates exit code to the broadcast stream" do
      stub_connection current_user: users(:admin)
      fake = FakeTerminalSession.new(server: servers(:one))

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        stream = stream_name_for(subscription)
        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])

        expect { fake.simulate_exit(7) }.to have_broadcasted_to(stream).with(hash_including(type: "exit", code: 7))
      end
    end
  end

  describe "output propagation" do
    it "base64-encodes output and broadcasts as stdout" do
      stub_connection current_user: users(:admin)
      fake = FakeTerminalSession.new(server: servers(:one))

      with_fake_session(fake) do
        subscribe server_id: servers(:one).id
        stream = stream_name_for(subscription)
        send_message("type" => "start", "mode" => "shell", "target" => nil, "argv" => [])

        expected_b64 = Base64.strict_encode64("hello")
        expect { fake.simulate_output("hello") }
          .to have_broadcasted_to(stream).with(hash_including(type: "stdout", data: expected_b64))
      end
    end
  end

  describe "TerminalSession.new kwargs" do
    it "receives mode :enter with the correct target" do
      stub_connection current_user: users(:one)
      app = app_records(:one)

      captured = with_capturing_session do
        subscribe server_id: servers(:one).id
        send_message("type" => "start", "mode" => "enter", "target" => app.name, "argv" => [])
      end

      expect(captured).not_to be_nil
      expect(captured[:mode]).to eq(:enter)
      expect(captured[:target]).to eq(app.name)
    end

    it "receives mode :db_connect with service_type as db_kind" do
      stub_connection current_user: users(:one)
      db = database_services(:one)

      captured = with_capturing_session do
        subscribe server_id: servers(:one).id
        send_message("type" => "start", "mode" => "db_connect", "target" => db.name, "argv" => [])
      end

      expect(captured).not_to be_nil
      expect(captured[:mode]).to eq(:db_connect)
      expect(captured[:target]).to eq(db.name)
      expect(captured[:db_kind]).to eq(db.service_type)
    end
  end
end
