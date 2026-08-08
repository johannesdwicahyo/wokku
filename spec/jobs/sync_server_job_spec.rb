# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncServerJob, type: :job do
  let(:server) { servers(:one) }

  it "marks the server connected without touching dokku (B6 quiescence)" do
    # Every record class this job once reconciled is control-plane-owned;
    # dokku's lists are dead metadata and dokku leaves the host at W8.
    server.update_column(:status, Server.statuses[:syncing])
    expect(Hosts::Ssh).not_to receive(:new)

    described_class.perform_now(server.id)

    expect(server.reload.status).to eq("connected")
  end

  it "never creates, destroys, or mutates app/domain/database records" do
    before_counts = [ AppRecord.count, Domain.count, DatabaseService.count ]

    described_class.perform_now(server.id)

    expect([ AppRecord.count, Domain.count, DatabaseService.count ]).to eq(before_counts)
  end
end
