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

  # Security assessment 2026-11-19, F-05: the host app enforces a CSP without
  # 'unsafe-inline' for scripts, so admin-authored <script> tags carry the
  # request's nonce (they're trusted: only a system admin can set them).
  it "stamps the CSP nonce on admin <script> tags" do
    SiteSetting.current.update!(body_scripts: %(<script src="https://w.example/widget.js"></script><SCRIPT>x()</SCRIPT><style>a{}</style>))
    allow(view).to receive(:content_security_policy_nonce).and_return("abc123")
    render partial: "shared/addon_scripts"
    expect(rendered.scan(/<script nonce="abc123"/i).size).to eq(2)
    expect(rendered).to include("<style>a{}</style>")
  end

  it "leaves scripts alone when the app has no CSP nonce" do
    SiteSetting.current.update!(body_scripts: "<script>x()</script>")
    allow(view).to receive(:content_security_policy_nonce).and_return(nil)
    render partial: "shared/addon_scripts"
    expect(rendered).to include("<script>x()</script>")
  end
end
