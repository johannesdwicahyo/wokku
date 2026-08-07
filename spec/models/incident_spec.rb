# frozen_string_literal: true

require "rails_helper"

RSpec.describe Incident do
  describe ".open! / .open_for / #resolve!" do
    it "opens one incident per subject and is idempotent while open" do
      app = create(:app_record)
      first = Incident.open!(subject: app, reason: "http_5xx")
      again = Incident.open!(subject: app, reason: "timeout")

      expect(again.id).to eq(first.id)
      expect(Incident.open_for(app)).to eq(first)
      expect(first.reload.reason).to eq("http_5xx") # first reason wins

      first.resolve!
      expect(Incident.open_for(app)).to be_nil
      expect(first.reload.resolved_at).to be_present

      second = Incident.open!(subject: app, reason: "timeout")
      expect(second.id).not_to eq(first.id)
    end

    it "works with a Server subject too" do
      server = create(:server)
      incident = Incident.open!(subject: server, reason: "host_down")
      expect(incident.server_id).to eq(server.id)
      expect(Incident.open_for(server)).to eq(incident)
    end

    it "rejects a row with both subjects (DB check constraint)" do
      app = create(:app_record)
      server = create(:server)
      expect {
        Incident.create!(app_record: app, server: server, reason: "x", started_at: Time.current)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rejects a second OPEN incident for the same subject (partial unique index)" do
      app = create(:app_record)
      create(:incident, app_record: app)
      expect {
        Incident.create!(app_record: app, reason: "y", started_at: Time.current)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
