# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrPreviewDeployJob, type: :job do
  it "forwards to Preview::Deployer" do
    parent = create(:app_record)
    deployer = instance_double(Preview::Deployer, call: true)
    expect(Preview::Deployer).to receive(:new).with(parent: parent, event: instance_of(Preview::PrEvent)).and_return(deployer)
    described_class.new.perform(
      parent_app_id: parent.id, pr_number: 1, branch: "x",
      commit_sha: "abc", pr_title: "t", repo_full_name: "o/r"
    )
  end
end
