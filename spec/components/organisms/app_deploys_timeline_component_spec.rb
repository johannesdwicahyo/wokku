require "rails_helper"

RSpec.describe Organisms::AppDeploysTimelineComponent, type: :component do
  let(:app) { create(:app_record, name: "shop") }

  def release(v, status)
    d = create(:deploy, app_record: app, status: status, image_ref: "127.0.0.1:5000/x/shop:#{v}")
    Release.create!(app_record: app, deploy: d, version: v)
  end

  def render_it(releases, can_update: true)
    render_inline(described_class.new(app: app, releases: releases, current_release: Organisms::AppHeaderComponent.current_release(releases), can_update: can_update))
  end

  it "tags live and failed, rolls back only older succeeded, logs failures" do
    rs = [ release(3, :failed), release(2, :succeeded), release(1, :succeeded) ]
    render_it(rs)
    expect(page.find("[data-release='2']")).to have_text("Live")
    expect(page.find("[data-release='3']")).to have_text("Failed").and have_link("Log")
    expect(page.find("[data-release='1']")).to have_button("Roll back")
    expect(page).to have_button("Roll back", count: 1)
  end

  it "hides Roll back for viewers" do
    render_it([ release(2, :succeeded), release(1, :succeeded) ], can_update: false)
    expect(page).to have_no_button("Roll back")
  end

  it "caps at 4 rows and has an empty state" do
    render_it((1..6).map { |v| release(v, :succeeded) }.reverse)
    expect(page).to have_css("li", count: 4)
    render_it([])
    expect(page).to have_text("No deploys yet")
  end
end
