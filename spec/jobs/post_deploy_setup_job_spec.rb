# frozen_string_literal: true

require "rails_helper"

RSpec.describe PostDeploySetupJob, type: :job do
  let(:app) { app_records(:one) }

  before do
    allow_any_instance_of(Dokku::Client).to receive(:run).and_return("ports: http:80:5000")
    allow_any_instance_of(Cloudflare::Dns).to receive(:create_app_record).and_return(nil)
  end

  it "returns early when app not found" do
    expect_any_instance_of(Cloudflare::Dns).not_to receive(:create_app_record)
    described_class.perform_now("00000000-0000-7000-8000-000000000000")
  end

  it "creates a Domain record for the default wokku.cloud subdomain" do
    expect { described_class.perform_now(app.id) }.to change { app.domains.count }.by(1)
    expect(app.domains.exists?(hostname: "#{app.name}.wokku.cloud")).to be true
  end

  it "swallows Cloudflare errors and still sets up the rest" do
    allow_any_instance_of(Cloudflare::Dns).to receive(:create_app_record)
      .and_raise(StandardError, "cloudflare down")
    expect { described_class.perform_now(app.id) }.not_to raise_error
    expect(app.reload.domains.exists?(hostname: "#{app.name}.wokku.cloud")).to be true
  end

  it "swallows Dokku connection errors entirely" do
    allow_any_instance_of(Dokku::Client).to receive(:run)
      .and_raise(Dokku::Client::ConnectionError, "ssh")
    expect { described_class.perform_now(app.id) }.not_to raise_error
  end

  it "is idempotent — running twice doesn't create duplicate domain" do
    described_class.perform_now(app.id)
    expect { described_class.perform_now(app.id) }.not_to change { app.domains.count }
  end

  it "sets letsencrypt global email before enable when env present" do
    ENV["LETSENCRYPT_EMAIL"] = "ops@example.com"
    commands = []
    allow_any_instance_of(Dokku::Client).to receive(:run) { |_, cmd| commands << cmd; "" }
    described_class.perform_now(app.id)
    expect(commands.any? { |c| c.include?("letsencrypt:set --global email") }).to be true
  ensure
    ENV.delete("LETSENCRYPT_EMAIL")
  end

  it "rewrites detected non-80 mapping to http:80 (Rails 3000 case)" do
    report = "Ports map:        \n       Ports map detected: https:3000:3000\n"
    commands = []
    allow_any_instance_of(Dokku::Client).to receive(:run) { |_, cmd| commands << cmd; report }
    described_class.perform_now(app.id)
    expect(commands.any? { |c| c =~ /ports:set .* http:80:3000/ }).to be true
  end

  it "skips port rewrite when http:80 mapping already correct" do
    report = "Ports map:        http:80:5000\n       Ports map detected: http:80:5000\n"
    commands = []
    allow_any_instance_of(Dokku::Client).to receive(:run) { |_, cmd| commands << cmd; report }
    described_class.perform_now(app.id)
    expect(commands.any? { |c| c.include?("ports:set") }).to be false
  end

  it "skips letsencrypt email set when no env configured" do
    original_le = ENV.delete("LETSENCRYPT_EMAIL")
    original_admin = ENV.delete("ADMIN_EMAIL")
    commands = []
    allow_any_instance_of(Dokku::Client).to receive(:run) { |_, cmd| commands << cmd; "" }
    described_class.perform_now(app.id)
    expect(commands.any? { |c| c.include?("letsencrypt:set --global email") }).to be false
  ensure
    ENV["LETSENCRYPT_EMAIL"] = original_le if original_le
    ENV["ADMIN_EMAIL"] = original_admin if original_admin
  end
end
