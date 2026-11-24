require "rails_helper"

RSpec.describe Organisms::AppDeletionProgressComponent, type: :component do
  def progress(state, steps) = { app_name: "shop", team_id: 1, state: state, steps: steps }

  it "blocks the page and shows a spinner on the running step" do
    render_inline(described_class.new(app_id: "a1", progress: progress("running", [
      { label: "Queued", state: "done" }, { label: "Removing DNS records", state: "running" }
    ])))
    expect(page).to have_css("#app_deletion_a1.fixed.inset-0")
    expect(page).to have_text("Deleting shop…")
    expect(page).to have_css("li .wk-lights")
    expect(page).not_to have_link("Close")
  end

  it "says done and offers Close when finished, flagging warning steps" do
    render_inline(described_class.new(app_id: "a1", progress: progress("done", [
      { label: "Removing DNS records", state: "warning" }
    ])))
    expect(page).to have_text("shop deleted")
    expect(page).to have_text("cleanup steps to retry")
    expect(page).to have_link("Close", href: "/dashboard/apps")
  end
end
