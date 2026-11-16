require "rails_helper"

RSpec.describe TemplatePricingHelper, type: :helper do
  let(:template) { { addons: [ { "type" => "postgres" } ] } }

  before { allow(helper).to receive(:wokku_cloud?).and_return(false) }

  it "says 'database' where shared add-ons don't exist (self-host)" do
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(false)
    expect(helper.template_total_label(template)).to eq("1 Small box + 1 database")
  end

  it "says 'shared add-on' where they do" do
    allow(Addons::SharedProvisioner).to receive(:feature_enabled?).and_return(true)
    expect(helper.template_total_label(template)).to eq("1 Small box + 1 shared add-on")
  end
end
