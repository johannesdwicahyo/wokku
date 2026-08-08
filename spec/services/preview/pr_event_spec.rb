require "rails_helper"

RSpec.describe Preview::PrEvent do
  it "stores all attributes and freezes" do
    event = described_class.new(
      provider: :github,
      action: :opened,
      pr_number: 7,
      branch: "feat/x",
      sha: "abc123",
      repo_full_name: "octo/repo",
      title: "Add feature",
      installation_id: 42,
      author: "octocat"
    )
    expect(event.provider).to eq(:github)
    expect(event.action).to eq(:opened)
    expect(event.pr_number).to eq(7)
    expect(event.branch).to eq("feat/x")
    expect(event.sha).to eq("abc123")
    expect(event.repo_full_name).to eq("octo/repo")
    expect(event.installation_id).to eq(42)
    expect(event).to be_frozen
  end

  it "deploy_action? is true for opened/synchronize/reopened" do
    %i[opened synchronize reopened].each do |a|
      e = build_event(action: a)
      expect(e.deploy_action?).to be(true), "expected #{a} to be deploy"
    end
  end

  it "cleanup_action? is true for closed/merged" do
    %i[closed merged].each do |a|
      expect(build_event(action: a).cleanup_action?).to be(true)
    end
  end

  it "deploy_action? is false for closed/merged" do
    %i[closed merged].each do |a|
      expect(build_event(action: a).deploy_action?).to be(false), "expected #{a} not to be deploy"
    end
  end

  it "cleanup_action? is false for opened/synchronize/reopened" do
    %i[opened synchronize reopened].each do |a|
      expect(build_event(action: a).cleanup_action?).to be(false), "expected #{a} not to be cleanup"
    end
  end

  def build_event(**overrides)
    described_class.new(
      provider: :github, action: :opened, pr_number: 1,
      branch: "x", sha: "abc", repo_full_name: "o/r",
      title: "t", installation_id: nil, author: "u",
      **overrides
    )
  end
end
