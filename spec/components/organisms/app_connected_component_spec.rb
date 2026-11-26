require "rails_helper"

RSpec.describe Organisms::AppConnectedComponent, type: :component do
  let(:app) { create(:app_record) }

  it "shows the env var name" do
    svc = create(:database_service, service_type: "redis")
    AppDatabase.create!(app_record: app, database_service: svc, alias_name: "REDIS")
    render_inline(described_class.new(app: app))
    expect(page).to have_text("redis · REDIS_URL")
  end

  it "has an empty state" do
    render_inline(described_class.new(app: app))
    expect(page).to have_text("No add-ons connected")
  end
end
