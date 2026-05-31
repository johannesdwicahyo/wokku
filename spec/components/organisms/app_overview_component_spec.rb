require "rails_helper"

RSpec.describe Organisms::AppOverviewComponent, type: :component do
  let(:app) { create(:app_record, name: "my-rails-app") }
  let(:user) { app.creator }

  before do
    # ViewComponent specs run without Warden middleware, so
    # `helpers.current_user` blows up. Patch every helpers proxy used
    # by any rendered component in this spec to return the test user.
    # Idempotent — re-applies the override per example so prepended
    # modules survive Devise's lazy autoload between examples.
    warden_double = double("Warden::Proxy", authenticate: user, user: user, authenticate?: true)
    allow_any_instance_of(ActionDispatch::Request).to receive(:env)
      .and_wrap_original do |original|
        env = original.call
        env["warden"] ||= warden_double
        env
      end
  end

  it "renders status pill + memory + action buttons" do
    render_inline(described_class.new(app: app))
    expect(page).to have_css("[data-controller~=\"motion--status-pulse\"]")
    expect(page).to have_text(/memory/i)
    expect(page).to have_button("restart")
    expect(page).to have_button("stop")
    expect(page).to have_link("scale ↗")
  end

  it "shows DB + KV + Backups summary cards" do
    render_inline(described_class.new(app: app))
    expect(page).to have_text("// postgres")
    expect(page).to have_text("// redis")
    expect(page).to have_text("// backups")
  end

  # Regression coverage for the 2026-05-29 prod 500. `Domain` has
  # `hostname`, not `name` — the previous code called the wrong method
  # and crashed any /dashboard/apps/<id> render where the app had Domain
  # rows.
  describe "#display_url" do
    let(:component) { described_class.new(app: app) }

    it "renders the canonical *.wokku.cloud subdomain when no custom domain is attached" do
      expect(component.display_url).to eq("https://my-rails-app.wokku.cloud")
    end

    it "renders the wokku-owned hostname when only Wokku subdomains are attached" do
      app.domains.create!(hostname: "my-rails-app.wokku.cloud")
      expect(component.display_url).to eq("https://my-rails-app.wokku.cloud")
    end

    it "prefers a custom domain when one is attached" do
      app.domains.create!(hostname: "my-rails-app.wokku.cloud")
      app.domains.create!(hostname: "shop.example.com")
      expect(component.display_url).to eq("https://shop.example.com")
    end
  end
end
