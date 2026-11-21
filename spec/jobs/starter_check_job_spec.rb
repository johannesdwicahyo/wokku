require "rails_helper"

RSpec.describe StarterCheckJob do
  include ActiveJob::TestHelper

  # Single-admin rule: reuse the seeded admin when there is one.
  let!(:admin) do
    (User.admin.first || create(:user, :admin)).tap do |u|
      TeamMembership.create!(user: u, team: create(:team), role: :admin) if u.teams.empty?
    end
  end
  let!(:server) { create(:server) }
  let(:template) { { slug: "go", repo: "https://github.com/johannesdwicahyo/wokku-go-starter" } }
  let(:deployer) { instance_double(TemplateDeployer) }

  before do
    allow_any_instance_of(Server).to receive(:wokkud_services_enabled?).and_return(true)
    allow_any_instance_of(TemplateRegistry).to receive(:find).with("go").and_return(template)
    allow(TemplateDeployer).to receive(:new).and_return(deployer)
  end

  def throwaway_app
    create(:app_record, name: "zz-starter-go", server: server, team: admin.teams.first)
  end

  it "picks only the wokku-*-starter repo templates" do
    allow_any_instance_of(TemplateRegistry).to receive(:all).and_return([
      template, { slug: "ghost", repo: "" }, { slug: "rails", repo: "https://github.com/johannesdwicahyo/wokku-rails-starter" }
    ])
    expect(described_class.starter_slugs).to eq(%w[go rails])
  end

  it "deploys the first starter and schedules a check of its build" do
    allow(deployer).to receive(:deploy!) { throwaway_app; { async: true } }
    expect { described_class.perform_now(%w[go rails], {}) }
      .to have_enqueued_job(described_class).with(%w[go rails], {}, kind_of(String), kind_of(String), 0)
  end

  it "records a refused deploy and moves on to the next starter" do
    allow(deployer).to receive(:deploy!).and_return({ success: false, error: "quota" })
    expect { described_class.perform_now(%w[go rails], {}) }
      .to have_enqueued_job(described_class).with(%w[rails], { "go" => "deploy refused: quota" })
  end

  it "passes a starter whose deploy succeeded and whose URL answers, then deletes the app" do
    app = throwaway_app
    create(:deploy, app_record: app, status: :succeeded)
    allow_any_instance_of(described_class).to receive(:probe).and_return(200)
    expect { described_class.perform_now(%w[go], {}, app.id, Time.current.iso8601, 0) }
      .to have_enqueued_job(AppDestroyJob).with(app.id)
      .and have_enqueued_job(described_class).with([], { "go" => "ok" })
  end

  it "fails a starter whose build failed, with the end of its log" do
    app = throwaway_app
    create(:deploy, app_record: app, status: :failed, log: "step 1\ngo: toolchain not available")
    expect { described_class.perform_now(%w[go], {}, app.id, Time.current.iso8601, 0) }
      .to have_enqueued_job(described_class).with([], { "go" => a_string_including("build failed", "toolchain not available") })
  end

  it "keeps polling a running build, and gives up after the build timeout" do
    app = throwaway_app
    create(:deploy, app_record: app, status: :building)
    expect { described_class.perform_now(%w[go], {}, app.id, Time.current.iso8601, 0) }
      .to have_enqueued_job(described_class).with(%w[go], {}, app.id, kind_of(String), 0)
    expect { described_class.perform_now(%w[go], {}, app.id, 30.minutes.ago.iso8601, 0) }
      .to have_enqueued_job(described_class).with([], { "go" => a_string_including("no finished deploy") })
  end

  describe "#probe" do
    let(:app) { throwaway_app.tap { |a| a.domains.create!(hostname: "zz-starter-go.wokku.app") } }

    it "does not count Caddy's empty no-route 200 as the app answering" do
      stub_request(:get, "https://zz-starter-go.wokku.app/").to_return(status: 200, body: "")
      expect(described_class.new.send(:probe, app)).to be_nil
    end

    it "returns the app's own status code" do
      stub_request(:get, "https://zz-starter-go.wokku.app/").to_return(status: 404, body: "<h1>Not Found</h1>")
      expect(described_class.new.send(:probe, app)).to eq(404)
    end
  end

  it "emails the operator only when something failed" do
    expect { described_class.perform_now([], { "go" => "ok" }) }.not_to have_enqueued_mail(OpsMailer, :starter_check_failed)
    expect { described_class.perform_now([], { "go" => "ok", "rails" => "build failed" }) }
      .to have_enqueued_mail(OpsMailer, :starter_check_failed).with({ "rails" => "build failed" }, 2)
  end
end
