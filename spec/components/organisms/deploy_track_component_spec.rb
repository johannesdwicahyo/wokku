require "rails_helper"

RSpec.describe Organisms::DeployTrackComponent, type: :component do
  let(:app) { create(:app_record) }
  let(:deploy) { create(:deploy, app_record: app, status: :building, commit_sha: "4f2a91cabcdef", log: (1..15).map { |i| "line #{i}" }.join("\n")) }

  before { app.releases.create!(description: "r", version: 14) }

  it "renders nothing without a deploy" do
    render_inline(described_class.new(deploy: nil))
    expect(page.text).to be_blank
  end

  it "shows the app, next version, sha and an Open log link" do
    render_inline(described_class.new(deploy: deploy))
    expect(page).to have_text("#{app.name} → v15")
    expect(page).to have_text("4f2a91c")
    expect(page).to have_link("Open log", href: "/dashboard/apps/#{app.id}/deploys/#{deploy.id}")
  end

  it "shows the deploy's own release version, not latest + 1" do
    rel = app.releases.create!(description: "mine", version: 20)
    own = create(:deploy, app_record: app, status: :building, release: rel)
    render_inline(described_class.new(deploy: own))
    expect(page).to have_text("#{app.name} → v20")
  end

  it "marks Push done, Build running, Release/Live pending, with no percentage" do
    render_inline(described_class.new(deploy: deploy))
    expect(page).to have_css("[data-stage=push][data-state=done]")
    expect(page).to have_css("[data-stage=build][data-state=run] i", count: 8)
    expect(page).to have_css("[data-stage=release][data-state=pending]")
    expect(page).to have_css("[data-stage=live][data-state=pending]")
    expect(page).to have_no_text("%")
  end

  it "shows only the last 12 log lines, escaped" do
    deploy.update!(log: "<script>x</script>\n" + (1..12).map { |i| "l#{i}" }.join("\n"))
    render_inline(described_class.new(deploy: deploy))
    log = page.find("[data-deploy-target=output]")
    expect(log.text).not_to include("script")
    expect(log.text).to include("l12")
    expect(page.native.to_html).not_to include("<script>")
  end

  it "truncates a long log to 12 lines" do
    render_inline(described_class.new(deploy: deploy))
    text = page.find("[data-deploy-target=output]").text
    expect(text).not_to include("line 3\n")
    expect(text).to include("line 4")
    expect(text).to include("line 15")
  end

  it "wires the deploy controller to reload the apps list frame" do
    render_inline(described_class.new(deploy: deploy))
    el = page.find("[data-controller=deploy]")
    expect(el["data-deploy-deploy-id-value"]).to eq(deploy.id)
    expect(el["data-deploy-reload-frame-value"]).to eq("apps_list")
    expect(el["aria-live"]).to eq("off")
  end

  it "shows +N more" do
    render_inline(described_class.new(deploy: deploy, more: 2))
    expect(page).to have_text("+2 more")
  end

  it "renders in Indonesian" do
    I18n.with_locale(:id) { render_inline(described_class.new(deploy: deploy, more: 2)) }
    expect(page).to have_text("Deploy berjalan")
    expect(page).to have_text("+2 lagi")
    expect(page).to have_text("Buka log")
  end
end
