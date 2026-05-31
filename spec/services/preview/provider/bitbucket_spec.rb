require "rails_helper"

RSpec.describe Preview::Provider::Bitbucket do
  def load_fixture(name)
    JSON.parse(File.read(Rails.root.join("spec/fixtures/webhooks/bitbucket/#{name}.json")))
  end

  describe ".parse" do
    it "parses pullrequest:created → :opened" do
      event = described_class.parse(load_fixture("pullrequest_created"), event_key: "pullrequest:created")
      expect(event.provider).to eq(:bitbucket)
      expect(event.action).to eq(:opened)
      expect(event.pr_number).to eq(7)
      expect(event.branch).to eq("feat/x")
      expect(event.sha).to eq("abc123def")
      expect(event.repo_full_name).to eq("octo/repo")
      expect(event.author).to eq("octocat")
    end

    it "parses pullrequest:updated → :synchronize" do
      event = described_class.parse(load_fixture("pullrequest_updated"), event_key: "pullrequest:updated")
      expect(event.action).to eq(:synchronize)
    end

    it "parses pullrequest:fulfilled → :merged" do
      event = described_class.parse(load_fixture("pullrequest_fulfilled"), event_key: "pullrequest:fulfilled")
      expect(event.action).to eq(:merged)
    end

    it "parses pullrequest:rejected → :closed" do
      event = described_class.parse(load_fixture("pullrequest_rejected"), event_key: "pullrequest:rejected")
      expect(event.action).to eq(:closed)
    end
  end
end
