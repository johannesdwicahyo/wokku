require "rails_helper"

RSpec.describe Preview::Provider::Gitlab do
  def load_fixture(name)
    JSON.parse(File.read(Rails.root.join("spec/fixtures/webhooks/gitlab/#{name}.json")))
  end

  describe ".parse" do
    it "parses opened action" do
      event = described_class.parse(load_fixture("merge_request_opened"))
      expect(event.provider).to eq(:gitlab)
      expect(event.action).to eq(:opened)
      expect(event.pr_number).to eq(7)
      expect(event.branch).to eq("feat/x")
      expect(event.sha).to eq("abc123def")
      expect(event.repo_full_name).to eq("octo/repo")
      expect(event.author).to eq("octocat")
    end

    it "translates update → :synchronize" do
      event = described_class.parse(load_fixture("merge_request_updated"))
      expect(event.action).to eq(:synchronize)
    end

    it "translates close → :closed" do
      event = described_class.parse(load_fixture("merge_request_closed"))
      expect(event.action).to eq(:closed)
    end

    it "translates merge → :merged" do
      event = described_class.parse(load_fixture("merge_request_merged"))
      expect(event.action).to eq(:merged)
    end
  end
end
