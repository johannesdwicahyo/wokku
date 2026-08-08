require "rails_helper"

RSpec.describe Preview::DeployJob do
  it "constructs PrEvent and calls Deployer" do
    parent = create(:app_record)
    attrs = { provider: :github, action: :opened, pr_number: 1, branch: "x",
              sha: "abc", repo_full_name: "o/r", title: "t",
              installation_id: 1, author: "u" }
    deployer = instance_double(Preview::Deployer, call: true)
    expect(Preview::Deployer).to receive(:new).with(parent: parent, event: instance_of(Preview::PrEvent)).and_return(deployer)
    described_class.new.perform(parent.id, attrs)
  end

  it "supports stringified hash keys (ActiveJob serialization)" do
    parent = create(:app_record)
    attrs = { "provider" => "github", "action" => "opened", "pr_number" => 1, "branch" => "x",
              "sha" => "abc", "repo_full_name" => "o/r", "title" => "t",
              "installation_id" => 1, "author" => "u" }
    deployer = instance_double(Preview::Deployer, call: true)
    expect(Preview::Deployer).to receive(:new).and_return(deployer)
    expect { described_class.new.perform(parent.id, attrs) }.not_to raise_error
  end
end
