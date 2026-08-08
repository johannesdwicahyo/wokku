# frozen_string_literal: true

require "rails_helper"

RSpec.describe Apps::LogReader do
  let(:server) { create(:server) }
  let(:client) { instance_double(Hosts::Ssh) }

  before { allow(Hosts::Ssh).to receive(:new).and_return(client) }

  describe ".recent" do
    it "reads Swarm service logs" do
      app = create(:app_record, server: server, name: "myapp", wokkud_lifecycle: true)
      expect(client).to receive(:run_raw)
        .with(a_string_matching(/docker service ls --filter label=wokku\.app=myapp.*docker service logs --tail 50/m))
        .and_return("2026-07-19T00:00:00Z hello")

      expect(described_class.recent(app, lines: 50)).to eq("2026-07-19T00:00:00Z hello")
    end

    it "explains an empty result instead of showing nothing" do
      app = create(:app_record, server: server, wokkud_native: true)
      allow(client).to receive(:run_raw).and_return("")

      expect(described_class.recent(app)).to include("deploy first")
    end
  end

  describe ".tail" do
    it "follows the web Swarm service" do
      app = create(:app_record, server: server, name: "myapp", wokkud_lifecycle: true)
      expect(client).to receive(:run_raw_streaming)
        .with(a_string_including("docker service logs --follow --tail 50 --timestamps wokku-myapp-web"))

      described_class.tail(app) { }
    end
  end
end
