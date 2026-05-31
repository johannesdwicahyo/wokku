require "rails_helper"

RSpec.describe Molecules::BackupsSummaryCardComponent, type: :component do
  before { %i[free solo pro team].each { |k| Plan.find_or_create_by!(key: k.to_s) { |p| p.name = k.to_s.capitalize } } }

  let(:app) { double(name: "demo", respond_to?: false) }

  it "renders 'On-demand only' for Free users (retention = 0)" do
    user = double(plan: Plan.find_by(key: "free"))
    render_inline(described_class.new(app: app, current_user: user))
    expect(page).to have_text("On-demand only")
  end

  it "renders 'Daily · 7-day retention' for Pro users" do
    pro = Plan.find_by(key: "pro").tap { |p| p.update!(backup_retention_days: 7) }
    user = double(plan: pro)
    render_inline(described_class.new(app: app, current_user: user))
    expect(page).to have_text("Daily · 7-day retention")
  end

  it "falls back gracefully when current_user is nil" do
    render_inline(described_class.new(app: app, current_user: nil))
    expect(page).to have_text("On-demand only")
  end

  it "shows 'No database attached' when app has no primary_database" do
    no_db_app = double(name: "demo", primary_database: nil, last_backup: nil).tap do |d|
      allow(d).to receive(:respond_to?).with(:last_backup).and_return(true)
      allow(d).to receive(:respond_to?).with(:primary_database).and_return(true)
    end
    user = double(plan: Plan.find_by(key: "solo"))
    render_inline(described_class.new(app: no_db_app, current_user: user))
    expect(page).to have_text(/No database attached/i)
    expect(page).not_to have_button("backup now")
  end

  it "renders 'backup now' control when app has a primary_database" do
    db = double(id: "db-1")
    app_with_db = double(name: "demo", id: "app-1", to_param: "app-1",
                        primary_database: db, last_backup: nil)
    allow(app_with_db).to receive(:respond_to?).with(:last_backup).and_return(true)
    allow(app_with_db).to receive(:respond_to?).with(:primary_database).and_return(true)
    user = double(plan: Plan.find_by(key: "solo"))
    render_inline(described_class.new(app: app_with_db, current_user: user))
    # button_to renders a form with a submit input; either the form's
    # action or the visible label is enough to prove the control mounted.
    expect(page.native.to_s).to include("backup_now").or include("backup now")
  end
end
