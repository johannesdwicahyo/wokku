# frozen_string_literal: true

require "rails_helper"

RSpec.describe Git::DeployForwarder do
  let(:user) { users(:one) }
  let(:app) { app_records(:one) }

  it "creates deploy and release records" do
    mock_client = Object.new
    mock_client.define_singleton_method(:run_streaming) { |_cmd, &block| block.call("-----> Building...\n") }

    original_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*_args| mock_client }
    begin
      described_class.new(user, app.name).forward

      deploy = app.deploys.order(:created_at).last
      expect(deploy).not_to be_nil
      expect(deploy.status).to eq("succeeded")
      expect(deploy.log).not_to be_nil
      expect(deploy.log).to include("Building")
      expect(deploy.started_at).not_to be_nil
      expect(deploy.finished_at).not_to be_nil

      release = deploy.release
      expect(release).not_to be_nil
      expect(release.description).to eq("Deploy via git push")
    ensure
      Dokku::Client.define_singleton_method(:new, original_new)
    end
  end

  it "marks deploy as failed on error" do
    mock_client = Object.new
    mock_client.define_singleton_method(:run_streaming) { |_cmd, &_block| raise StandardError, "connection lost" }

    original_new = Dokku::Client.method(:new)
    Dokku::Client.define_singleton_method(:new) { |*_args| mock_client }
    begin
      forwarder = described_class.new(user, app.name)

      expect { forwarder.forward }.to raise_error(StandardError)

      deploy = app.deploys.order(:created_at).last
      expect(deploy).not_to be_nil
      expect(deploy.status).to eq("failed")
      expect(deploy.log).to include("connection lost")
    ensure
      Dokku::Client.define_singleton_method(:new, original_new)
    end
  end

  it "raises NotAuthorizedError for unauthorized user" do
    unauthorized_user = users(:two)
    forwarder = described_class.new(unauthorized_user, app.name)
    expect { forwarder.forward }.to raise_error(Pundit::NotAuthorizedError)
  end

  it "raises RecordNotFound for non-existent app" do
    forwarder = described_class.new(user, "nonexistent-app")
    expect { forwarder.forward }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
