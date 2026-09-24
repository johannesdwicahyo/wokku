require "rails_helper"

RSpec.describe "Create app with a shape", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:user) { users(:one) }
  before { sign_in user }

  it "creates the web allocation from the builder params" do
    post "/dashboard/apps", params: { app_record: { name: "shapeapp", server_id: servers(:one).id },
                                      processes: { web: { cpu: "0.5", memory_mb: "1024", count: "1", sleeping: "0" } } }
    app = AppRecord.find_by!(name: "shapeapp")
    expect(app.dyno_allocations.find_by(process_type: "web").shape.to_h).to include(cpu: 0.5, memory_mb: 1024)
  end
end
