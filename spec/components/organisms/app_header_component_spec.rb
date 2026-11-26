require "rails_helper"

RSpec.describe Organisms::AppHeaderComponent, type: :component do
  let(:app) { create(:app_record, name: "shop", github_repo_full_name: "acme/shop") }

  def release(version, status, image_ref: "127.0.0.1:5000/wokku-rollback/shop:#{version}")
    d = create(:deploy, app_record: app, status: status, image_ref: image_ref)
    Release.create!(app_record: app, deploy: d, version: version)
  end

  def render_header(releases: [], can_update: true)
    render_inline(described_class.new(app: app, releases: releases, can_update: can_update))
  end

  it "renders name, status light and domains with custom first" do
    create(:domain, app_record: app, hostname: "shop.example.com")
    render_header
    expect(page).to have_css("h1", text: "shop")
    expect(page).to have_css("[role=img][aria-label=Running]")
    hosts = page.all("a[href^='https://']").map(&:text)
    expect(hosts.first).to eq("shop.example.com")
    expect(hosts.last).to start_with("shop.")
    expect(page).to have_text("from GitHub acme/shop · main")
  end

  it "shows git push when no GitHub repo" do
    app.update!(github_repo_full_name: nil)
    render_header
    expect(page).to have_text("git push")
    expect(page).not_to have_button("Deploy main")
  end

  it "hides actions from viewers" do
    render_header(releases: [ release(1, :succeeded) ], can_update: false)
    expect(page).not_to have_button("Restart")
    expect(page).not_to have_button("Deploy main")
    expect(page).not_to have_css("button", text: "Roll back")
  end

  it "offers Restart, Deploy and Roll back to the newest non-current succeeded release" do
    rels = [ release(15, :succeeded), release(14, :succeeded), release(13, :failed) ]
    render_header(releases: rels)
    expect(page).to have_button("Restart")
    expect(page).to have_button("Deploy main")
    expect(page).to have_button("Roll back to v14")
    expect(page).not_to have_button("Roll back to v13")
  end

  it "hides Roll back when only the current release exists or it has no artifact" do
    render_header(releases: [ release(1, :succeeded) ])
    expect(page).not_to have_css("button", text: "Roll back")
    render_header(releases: [ release(3, :succeeded), release(2, :succeeded, image_ref: nil) ])
    expect(page).not_to have_css("button", text: "Roll back")
  end

  it "hides Deploy when deploys are locked" do
    app.update!(deploy_locked_at: Time.current)
    render_header
    expect(page).not_to have_button("Deploy main")
  end

  it "has no English labels under :id and keeps locale key parity" do
    I18n.with_locale(:id) { render_header(releases: [ release(2, :succeeded), release(1, :succeeded) ]) }
    expect(page).to have_button("Mulai ulang")
    expect(page).to have_button("Kembali ke v1")
    expect(page).not_to have_text("Restart")
    en = I18n.t("dashboard.app_header", locale: :en).keys
    expect(I18n.t("dashboard.app_header", locale: :id).keys).to match_array(en)
  end
end
