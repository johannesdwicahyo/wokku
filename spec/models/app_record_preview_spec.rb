require "rails_helper"

RSpec.describe AppRecord, type: :model do
  describe "preview scopes" do
    let!(:main_app) { create(:app_record, is_preview: false) }
    let!(:fresh_preview) do
      create(:app_record, is_preview: true, parent_app: main_app, pr_number: 1, last_commit_at: 1.hour.ago)
    end
    let!(:idle_preview) do
      create(:app_record, is_preview: true, parent_app: main_app, pr_number: 2, last_commit_at: 10.days.ago)
    end
    let!(:never_committed_preview) do
      create(:app_record, is_preview: true, parent_app: main_app, pr_number: 3, last_commit_at: nil)
    end

    it ".previews returns only preview apps" do
      expect(AppRecord.previews).to contain_exactly(fresh_preview, idle_preview, never_committed_preview)
    end

    it ".preview_idle_for(7.days) returns previews with no commits in window" do
      expect(AppRecord.preview_idle_for(7.days)).to contain_exactly(idle_preview)
    end

    it ".preview_idle_for(7.days) excludes previews with NULL last_commit_at" do
      expect(AppRecord.preview_idle_for(7.days)).not_to include(never_committed_preview)
    end
  end

  describe "#preview_subdomain" do
    let(:parent) { create(:app_record, name: "myapp", is_preview: false) }
    let(:preview) { build(:app_record, is_preview: true, parent_app: parent, pr_number: 7) }

    it "returns <parent>-pr-<N>" do
      expect(preview.preview_subdomain).to eq("myapp-pr-7")
    end

    it "returns nil for main apps" do
      expect(parent.preview_subdomain).to be_nil
    end
  end

  describe "#preview_hostname" do
    let(:parent) { create(:app_record, name: "myapp", is_preview: false) }
    let(:preview) { build(:app_record, is_preview: true, parent_app: parent, pr_number: 7) }

    it "returns <subdomain>.wokku.cloud" do
      expect(preview.preview_hostname).to eq("myapp-pr-7.wokku.cloud")
    end

    it "returns nil for main apps" do
      expect(parent.preview_hostname).to be_nil
    end
  end

  describe "preview_dns_record association" do
    let(:parent) { create(:app_record, name: "myapp", is_preview: false) }
    let(:preview) { create(:app_record, :preview, parent_app: parent, pr_number: 7) }

    it "destroys the dependent PreviewDnsRecord when destroyed" do
      preview.create_preview_dns_record!(hostname: "myapp-pr-7.wokku.cloud", cloudflare_record_id: "cf-1")
      expect { preview.destroy! }.to change(PreviewDnsRecord, :count).by(-1)
    end
  end
end
