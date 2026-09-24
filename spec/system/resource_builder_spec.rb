require "rails_helper"

RSpec.describe "Resource builder", type: :system, js: true do
  include Warden::Test::Helpers

  let(:user) { users(:one) }
  let(:app)  { app_records(:one) }

  before do
    driven_by(:selenium_chrome_headless)
    app.dyno_allocations.destroy_all
    app.dyno_allocations.create!(process_type: "web", count: 1, cpu: 0.25, memory_mb: 512)
    allow(Wokku.config).to receive(:pricing).and_return(
      double(unit_prices: { "cpu" => 16_000, "memory_gb" => 24_000, "disk_gb" => 1_000 }, monthly_idr: 16_000)
    )
    login_as user, scope: :user
  end

  after { Warden.test_reset! }

  it "preset → live price → save converges with the new shape" do
    visit "/dashboard/apps/#{app.id}/resources"
    within("[data-controller='resource-builder']") do
      expect(page).to have_text("Rp16.000")
      click_button "Standard"
      expect(page).to have_text("Rp32.000")
    end
    expect { click_button "Save resources" }.to have_enqueued_job(ApplyResourcesJob)
    expect(app.dyno_allocations.find_by(process_type: "web").memory_mb).to eq(1024)
  end
end
