require "rails_helper"

RSpec.describe ImageScans::AfterReport do
  let(:server) { create(:server) }
  let(:app_record) { create(:app_record, server: server) }
  let(:deploy) { create(:deploy, :succeeded, app_record: app_record, log: "built\n") }
  let(:counts) { { "critical" => 0, "high" => 2, "fixable" => 1 } }

  def scan(trigger, deploy_id)
    ImageScan.create!(app_record: app_record, server: server, image_ref: "i:1", status: :succeeded, trigger: trigger, deploy_id: deploy_id, counts: counts)
  end

  it "appends the line once to the scan's own deploy and broadcasts it" do
    allow(DeployChannel).to receive(:broadcast_to)
    described_class.call(scan(:deploy, deploy.id))
    expect(deploy.reload.log).to eq("built\nImage scan: 0 critical · 2 high (1 fixable)\n")
    expect(DeployChannel).to have_received(:broadcast_to).once
  end

  it "is idempotent" do
    s = scan(:deploy, deploy.id)
    2.times { described_class.call(s) }
    expect(deploy.reload.log.scan("Image scan:").size).to eq 1
  end

  it "ignores nightly scans" do
    described_class.call(scan(:nightly, nil))
    expect(deploy.reload.log).to eq("built\n")
  end
end
