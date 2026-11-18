require "rails_helper"

# Host apps (wokku.cloud) append per-request scripts after the admin add-on
# scripts — e.g. a signed chat-widget identity — via their own
# shared/_host_scripts partial (engine views win, so they can't override this one).
RSpec.describe "shared/_addon_scripts", type: :view do
  it "renders the admin add-on scripts" do
    SiteSetting.current.update!(body_scripts: "<!-- admin -->")
    render partial: "shared/addon_scripts"
    expect(rendered).to include("<!-- admin -->")
  end

  it "appends a host app's shared/_host_scripts when one exists" do
    stub_template "shared/_host_scripts.html.erb" => "<!-- host -->"
    render partial: "shared/addon_scripts"
    expect(rendered).to include("<!-- host -->")
  end
end
