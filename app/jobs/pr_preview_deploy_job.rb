# Legacy entrypoint: kept for any jobs already enqueued in Solid Queue
# at deploy time. New events route through Preview::DeployJob via the
# webhook + EventDispatcher.
class PrPreviewDeployJob < ApplicationJob
  queue_as :deploys

  def perform(parent_app_id:, pr_number:, branch:, commit_sha:, pr_title:, repo_full_name:)
    parent = AppRecord.find(parent_app_id)
    event = Preview::PrEvent.new(
      provider: :github, action: :synchronize, pr_number: pr_number,
      branch: branch, sha: commit_sha, repo_full_name: repo_full_name,
      title: pr_title, installation_id: nil, author: ""
    )
    Preview::Deployer.new(parent: parent, event: event).call
  end
end
