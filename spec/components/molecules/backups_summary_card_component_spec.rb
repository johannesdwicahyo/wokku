require "rails_helper"

RSpec.describe Molecules::BackupsSummaryCardComponent, type: :component do
  let(:app) { double(name: "demo", respond_to?: false) }

  def app_with_db(db)
    double(name: "demo", id: "app-1", to_param: "app-1",
           primary_database: db, last_backup: nil).tap do |d|
      allow(d).to receive(:respond_to?).with(:last_backup).and_return(true)
      allow(d).to receive(:respond_to?).with(:primary_database).and_return(true)
    end
  end

  def db_with_policy(policy)
    double(id: "db-1", backup_policy: policy)
  end

  it "renders 'On-demand only' when the app has no database" do
    render_inline(described_class.new(app: app, current_user: double(plan: nil)))
    expect(page).to have_text("On-demand only")
  end

  it "renders the GFS keep-set for a basic-tier DB" do
    db = db_with_policy(ServiceTier::BACKUP_POLICIES["basic"])
    render_inline(described_class.new(app: app_with_db(db), current_user: nil))
    expect(page).to have_text("Daily · keeps 7 daily")
    expect(page).not_to have_text("weekly")
  end

  it "renders the full GFS keep-set for a standard-tier DB" do
    db = db_with_policy(ServiceTier::BACKUP_POLICIES["standard"])
    render_inline(described_class.new(app: app_with_db(db), current_user: nil))
    expect(page).to have_text("Daily · keeps 7 daily + 4 weekly + 1 monthly")
  end

  it "renders 'On-demand only' for a shared_free DB (no scheduled backups)" do
    db = db_with_policy(ServiceTier::BACKUP_POLICIES["shared_free"])
    render_inline(described_class.new(app: app_with_db(db), current_user: nil))
    expect(page).to have_text("On-demand only")
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
    render_inline(described_class.new(app: no_db_app, current_user: nil))
    expect(page).to have_text(/No database attached/i)
    expect(page).not_to have_button("backup now")
  end

  it "hides 'backup now' when the user cannot update, and localizes" do
    db = db_with_policy(ServiceTier::BACKUP_POLICIES["standard"])
    I18n.with_locale(:id) do
      render_inline(described_class.new(app: app_with_db(db), current_user: nil, can_update: false))
    end
    expect(page).not_to have_css("form")
    expect(page).to have_text("Harian · menyimpan 7 harian + 4 mingguan + 1 bulanan")
    expect(page).to have_text("Belum ada backup")
  end

  it "renders 'backup now' control when app has a primary_database" do
    db = db_with_policy(ServiceTier::BACKUP_POLICIES["basic"])
    render_inline(described_class.new(app: app_with_db(db), current_user: nil))
    # button_to renders a form with a submit input; either the form's
    # action or the visible label is enough to prove the control mounted.
    expect(page.native.to_s).to include("backup_now").or include("backup now")
  end
end
