require "rails_helper"

RSpec.describe Api::V1::Serializers::PreviewApp do
  let(:parent) { app_records(:one) }
  let(:preview) do
    parent.preview_apps.create!(
      name: "pr-42-myapp",
      server: parent.server,
      team: parent.team,
      created_by_id: parent.team.users.first.id,
      pr_number: 42,
      deploy_branch: "feat/foo",
      is_preview: true,
      status: :running
    )
  end

  it "serializes the public preview fields" do
    result = described_class.new(preview).call
    expect(result).to include(
      id: preview.id,
      name: "pr-42-myapp",
      pr_number: 42,
      branch: "feat/foo",
      status: "running"
    )
    expect(result).to have_key(:url) # url may be nil if preview_hostname is nil
  end

  it "uses preview_hostname for url when available" do
    allow(preview).to receive(:preview_hostname).and_return("pr-42-myapp.wokku.app")
    result = described_class.new(preview).call
    expect(result[:url]).to eq("https://pr-42-myapp.wokku.app")
  end

  it "renders url as nil when preview_hostname is nil" do
    allow(preview).to receive(:preview_hostname).and_return(nil)
    result = described_class.new(preview).call
    expect(result[:url]).to be_nil
  end
end
