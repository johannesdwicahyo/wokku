# frozen_string_literal: true

require "rails_helper"

RSpec.describe Apps::Restarter do
  let(:server) { create(:server) }

  it "rotates apps via converge (restart: true forces the Swarm update)" do
    app = create(:app_record, server: server, wokkud_lifecycle: true)
    expect(Lifecycle::Ops).to receive(:converge!).with(app, restart: true)
    expect(Hosts::Ssh).not_to receive(:new)

    described_class.restart(app)
  end
end
