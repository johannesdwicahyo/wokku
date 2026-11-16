require "rails_helper"

# One answer to "is this wokku.cloud?" — the billing host draws
# dashboard_billing; a self-host install (this harness) does not. Views,
# helpers and services all ask this instead of four ad-hoc checks.
RSpec.describe "Wokku.cloud?" do
  it "is false on a self-host install" do
    expect(Wokku.cloud?).to be(false)
  end

  it "is true when the billing host's route is drawn" do
    allow(Rails.application.routes.named_routes).to receive(:key?).and_call_original
    allow(Rails.application.routes.named_routes).to receive(:key?).with(:dashboard_billing).and_return(true)
    expect(Wokku.cloud?).to be(true)
  end

  it "is exposed to views as wokku_cloud?" do
    expect(ApplicationController.helpers.wokku_cloud?).to be(false)
  end
end
