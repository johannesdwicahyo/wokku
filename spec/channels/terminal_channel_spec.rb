# frozen_string_literal: true

require "rails_helper"

RSpec.describe TerminalChannel, type: :channel do
  # Fixtures already carry the single admin (DB-enforced), so reuse them
  # rather than create a second admin.
  let(:admin)  { users(:admin) }
  let(:member) { users(:one) }
  let(:server) { create(:server, team: teams(:one)) }

  # Capture the payloads the channel broadcasts to its private stream.
  def broadcasts
    @broadcasts ||= []
  end

  before do
    allow(ActionCable.server).to receive(:broadcast) { |_stream, payload| broadcasts << payload }
  end

  describe "#subscribed" do
    it "rejects when the server does not exist" do
      stub_connection current_user: admin
      subscribe(server_id: "00000000-0000-0000-0000-000000000000")
      expect(subscription).to be_rejected
    end

    it "rejects an unauthenticated connection" do
      stub_connection current_user: nil
      subscribe(server_id: server.id)
      expect(subscription).to be_rejected
    end

    it "subscribes an authorized user to a per-session stream" do
      stub_connection current_user: admin
      subscribe(server_id: server.id)
      expect(subscription).to be_confirmed
      expect(subscription.streams).to include(a_string_starting_with("terminal_#{server.id}_#{admin.id}_"))
    end
  end

  describe "#receive start validation (pre-SSH)" do
    def start(data)
      stub_connection current_user: current
      subscribe(server_id: server.id)
      perform :receive, { "type" => "start" }.merge(data)
    end

    context "as an admin" do
      let(:current) { admin }

      it "errors on an unknown mode" do
        start("mode" => "rm-rf")
        expect(broadcasts).to include(hash_including(type: "error", message: "unknown mode"))
      end

      it "errors when enter mode has no target" do
        start("mode" => "enter", "target" => "")
        expect(broadcasts).to include(hash_including(type: "error", message: "target required"))
      end

      it "errors when the target app is not found" do
        start("mode" => "exec", "target" => "no-such-app")
        expect(broadcasts).to include(hash_including(type: "error", message: "app not found or access denied"))
      end

      it "errors when the target database is not found" do
        start("mode" => "db_connect", "target" => "no-such-db")
        expect(broadcasts).to include(hash_including(type: "error", message: "database not found or access denied"))
      end
    end

    context "as a non-admin" do
      let(:current) { member }

      it "refuses shell mode without the admin role" do
        start("mode" => "shell")
        expect(broadcasts).to include(hash_including(type: "error", message: "shell mode requires admin role"))
      end
    end
  end

  describe "#receive start (session lifecycle)" do
    let(:session) do
      instance_double(TerminalSession, connect!: nil, connected?: false, disconnect!: nil)
    end

    before do
      allow(session).to receive(:on_output).and_yield("hi".b)
      allow(session).to receive(:on_exit).and_yield(0)
      allow(TerminalSession).to receive(:new).and_return(session)
      allow(Activity).to receive(:log)
      stub_connection current_user: admin
      subscribe(server_id: server.id)
    end

    def join_thread
      subscription.instance_variable_get(:@thread)&.join(2)
    end

    it "starts a shell session, wires callbacks, emits ready, and logs activity" do
      perform :receive, { "type" => "start", "mode" => "shell" }
      join_thread
      expect(TerminalSession).to have_received(:new)
        .with(server: server, mode: :shell, target: nil, argv: [], db_kind: nil)
      expect(broadcasts).to include(hash_including(type: "stdout"))
      expect(broadcasts).to include(hash_including(type: "exit", code: 0))
      expect(broadcasts).to include(hash_including(type: "ready"))
      expect(Activity).to have_received(:log)
        .with(hash_including(user: admin, team: server.team, action: "terminal.start"))
    end

    it "errors on a second start" do
      perform :receive, { "type" => "start", "mode" => "shell" }
      perform :receive, { "type" => "start", "mode" => "shell" }
      join_thread
      expect(broadcasts).to include(hash_including(type: "error", message: "already started"))
    end

    it "passes the database kind for db_connect mode" do
      db = create(:database_service, server: server, name: "prod-pg", service_type: "postgres")
      perform :receive, { "type" => "start", "mode" => "db_connect", "target" => db.name }
      join_thread
      expect(TerminalSession).to have_received(:new)
        .with(server: server, mode: :db_connect, target: "prod-pg", argv: [], db_kind: "postgres")
      expect(broadcasts).to include(hash_including(type: "ready"))
    end

    it "emits a spawn error when connect! raises" do
      allow(session).to receive(:connect!).and_raise(RuntimeError, "boom")
      perform :receive, { "type" => "start", "mode" => "shell" }
      expect(broadcasts).to include(hash_including(type: "error", message: "spawn failed: boom"))
      expect(broadcasts).not_to include(hash_including(type: "ready"))
    end
  end

  describe "stdin / resize / signal forwarding" do
    before do
      stub_connection current_user: admin
      subscribe(server_id: server.id)
    end

    it "forwards decoded stdin, resize, and INT to a connected session" do
      session = instance_double(TerminalSession, connected?: true)
      subscription.instance_variable_set(:@session, session)
      expect(session).to receive(:send_data).with("ls\n")
      perform :receive, { "type" => "stdin", "data" => Base64.strict_encode64("ls\n") }
      expect(session).to receive(:resize).with(120, 40)
      perform :receive, { "type" => "resize", "cols" => 120, "rows" => 40 }
      expect(session).to receive(:send_data).with("\x03")
      perform :receive, { "type" => "signal", "signal" => "INT" }
    end

    it "ignores stdin and signal when the session is not connected" do
      session = instance_double(TerminalSession, connected?: false)
      subscription.instance_variable_set(:@session, session)
      expect(session).not_to receive(:send_data)
      perform :receive, { "type" => "stdin", "data" => Base64.strict_encode64("x") }
      perform :receive, { "type" => "signal", "signal" => "INT" }
    end
  end

  describe "#unsubscribed" do
    it "stops the loop and disconnects the session" do
      stub_connection current_user: admin
      subscribe(server_id: server.id)
      session = instance_double(TerminalSession, disconnect!: nil)
      subscription.instance_variable_set(:@session, session)
      subscription.unsubscribe_from_channel
      expect(session).to have_received(:disconnect!)
      expect(subscription.instance_variable_get(:@running)).to be(false)
    end
  end

  describe "#process_loop" do
    before do
      stub_connection current_user: admin
      subscribe(server_id: server.id)
    end

    it "disconnects and reports when the session times out" do
      session = instance_double(TerminalSession, connected?: true, process: nil,
                                                 timed_out?: true, disconnect!: nil)
      subscription.instance_variable_set(:@session, session)
      subscription.send(:process_loop)
      expect(broadcasts).to include(hash_including(type: "error", message: /timed out/))
      expect(session).to have_received(:disconnect!)
    end

    it "emits a session error and stops when process raises" do
      session = instance_double(TerminalSession, connected?: true)
      allow(session).to receive(:process).and_raise(IOError, "closed stream")
      subscription.instance_variable_set(:@session, session)
      subscription.send(:process_loop)
      expect(broadcasts).to include(hash_including(type: "error", message: "session error: closed stream"))
    end
  end
end
