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
end
