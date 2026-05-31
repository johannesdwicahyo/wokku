require "rails_helper"

RSpec.describe Organisms::AppsIndexComponent, type: :component do
  let(:plan) { create(:plan, :solo) }

  it "renders the empty state when no apps exist" do
    render_inline(described_class.new(apps: [], plan: plan, box_usage: {}, recent_activity: []))
    expect(page).to have_text(/No apps yet/i)
    expect(page).to have_link("From a template")
    expect(page).to have_link("From git")
  end

  it "renders the Apps heading and new app link" do
    render_inline(described_class.new(apps: [], plan: plan, box_usage: {}, recent_activity: []))
    expect(page).to have_css("h1", text: "Apps")
    expect(page).to have_link("+ new app")
  end

  context "when apps exist" do
    let(:team)  { create(:team) }
    let(:app)   { create(:app_record, team: team, name: "my-app") }

    it "renders status strip + table with app rows" do
      render_inline(described_class.new(
        apps: [ app ],
        plan: plan,
        box_usage: { "small" => 1 },
        recent_activity: []
      ))
      expect(page).to have_text("my-app")
      expect(page).to have_link("my-app")
      # Status strip: plan name appears in the box cell
      expect(page).to have_text(/solo · boxes/i)
    end

    it "renders the recent activity card (empty) when no events" do
      render_inline(described_class.new(
        apps: [ app ],
        plan: plan,
        box_usage: {},
        recent_activity: []
      ))
      expect(page).to have_text(/nothing here yet/i)
    end

    it "shows running count in the status strip" do
      running_app = create(:app_record, team: team, status: :running)
      render_inline(described_class.new(
        apps: [ running_app ],
        plan: plan,
        box_usage: {},
        recent_activity: []
      ))
      # The running count cell should contain "1"
      expect(page).to have_text("1")
    end
  end
end
