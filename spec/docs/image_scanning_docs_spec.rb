require "rails_helper"

RSpec.describe "Image scanning docs" do
  def page(loc) = File.read(File.expand_path("../../docs/content/#{loc}/monitoring/image-scanning.md", __dir__))

  it "quotes the clean state in each locale's own UI words" do
    %w[en id].each { |loc| expect(page(loc)).to include(I18n.t("apps.security.clean", locale: loc)) }
  end

  it "says both switches are needed per host" do
    expect(page("en")).to include("You need both").and include("Scanning…")
    expect(page("id")).to include("Keduanya wajib").and include(I18n.t("apps.security.scanning", locale: :id))
  end
end
