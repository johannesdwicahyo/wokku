require "rails_helper"

RSpec.describe Preview::Provider::GitHub do
  def load_fixture(name)
    JSON.parse(File.read(Rails.root.join("spec/fixtures/webhooks/github/#{name}.json")))
  end

  describe ".parse" do
    it "parses opened action" do
      event = described_class.parse(load_fixture("pull_request_opened"))
      expect(event.provider).to eq(:github)
      expect(event.action).to eq(:opened)
      expect(event.pr_number).to eq(7)
      expect(event.branch).to eq("feat/x")
      expect(event.sha).to eq("abc123def")
      expect(event.repo_full_name).to eq("octo/repo")
      expect(event.installation_id).to eq(42)
      expect(event.author).to eq("octocat")
    end

    it "translates closed+merged=true to :merged" do
      event = described_class.parse(load_fixture("pull_request_merged"))
      expect(event.action).to eq(:merged)
    end

    it "translates closed+merged=false to :closed" do
      event = described_class.parse(load_fixture("pull_request_closed"))
      expect(event.action).to eq(:closed)
    end
  end
end
