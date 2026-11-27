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

  describe "new critical notification" do
    include ActiveJob::TestHelper
    let(:app_deploy) { create(:deploy, :succeeded, app_record: app_record, image_ref: "i:1") }
    let!(:notification) { create(:notification, team: app_record.team, events: [ "image_scan_critical" ]) }

    before do
      allow(Wokku.config).to receive(:image_scans?).and_return(true)
      Release.create!(app_record: app_record, deploy: app_deploy, version: 1)
    end

    def crit(*ids, ref: "i:1", status: :succeeded, at: Time.current)
      ImageScan.create!(app_record: app_record, server: server, image_ref: ref, status: status, trigger: :nightly, created_at: at,
                        findings: ids.map { |i| { "id" => i, "severity" => "CRITICAL" } }, counts: { "critical" => ids.size })
    end

    def run(scan) = expect { described_class.call(scan) }.to have_enqueued_job(NotifyJob)

    it "notifies once for the first scan, with count, ids and findings link, and logs activity" do
      s = crit("CVE-1", "CVE-2")
      expect { 2.times { described_class.call(s) } }.to have_enqueued_job(NotifyJob).once.with(notification.id, "image_scan_critical", app_deploy.id, hash_including("count" => 2, "ids" => "CVE-1, CVE-2"))
      expect(Activity.where(action: "app.image_scan.critical").count).to eq 1
      msg = NotifyJob.new.send(:build_message, nil, "image_scan_critical", enqueued_jobs.last[:args].last)
      expect(msg).to include(app_record.name, "2", "/dashboard/apps/#{app_record.id}/image_scan")
    end

    it "does not notify when the same ids reappear" do
      crit("CVE-1", at: 2.hours.ago)
      expect { described_class.call(crit("CVE-1")) }.not_to have_enqueued_job(NotifyJob)
    end

    it "notifies with only the new id" do
      crit("CVE-1", at: 2.hours.ago)
      expect { described_class.call(crit("CVE-1", "CVE-9")) }.to have_enqueued_job(NotifyJob).with(anything, anything, anything, hash_including("count" => 1, "ids" => "CVE-9"))
    end

    it "ignores failed scans, a superseded image and a disabled feature" do
      expect { described_class.call(crit("CVE-1", status: :failed)) }.not_to have_enqueued_job(NotifyJob)
      expect { described_class.call(crit("CVE-1", ref: "i:0")) }.not_to have_enqueued_job(NotifyJob)
      allow(Wokku.config).to receive(:image_scans?).and_return(false)
      expect { described_class.call(crit("CVE-1")) }.not_to have_enqueued_job(NotifyJob)
    end
  end
end
