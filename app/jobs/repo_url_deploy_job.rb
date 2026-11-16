require "ipaddr"
require "resolv"

# Deploy from a public git repository URL: fetch into the app's own bare
# repo, then build through PushDeployer — the path repo templates and
# GithubDeployJob already take. This is how a self-hoster deploys their own
# code (no git gateway, usually no GitHub App).
class RepoUrlDeployJob < ApplicationJob
  queue_as :deploys

  # https only, and never a host that resolves to this machine or a private
  # network: the server does the fetch, so a URL must not reach inside.
  def self.valid_url?(url)
    uri = URI.parse(url.to_s)
    return false unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?

    host = uri.host.delete_prefix("[").delete_suffix("]")
    return false if host.casecmp?("localhost")

    addresses = host.match?(/\A[\d.]+\z|:/) ? [ host ] : Resolv.getaddresses(host)
    addresses.any? && addresses.none? { |a| internal?(a) }
  rescue URI::InvalidURIError
    false
  end

  def self.internal?(address)
    ip = IPAddr.new(address)
    ip.loopback? || ip.private? || ip.link_local? || ip.to_s == "0.0.0.0"
  rescue IPAddr::InvalidAddressError
    true
  end

  def perform(app_id:, deploy_id:, url:, branch:)
    app = AppRecord.find(app_id)
    deploy = Deploy.find(deploy_id)
    raise ArgumentError, "Repository URL must be a public https:// address" unless self.class.valid_url?(url)

    repo = Git::BareRepo.new(app.name)
    repo.ensure!
    GithubDeployJob.system_fetch(repo, url, branch)
    Git::PushDeployer.new(app, sha: resolve_sha(repo, branch), ref: "refs/heads/#{branch}", deploy: deploy).call
  rescue StandardError => e
    deploy&.update!(status: :failed, log: "Could not deploy #{url} (#{branch}): #{e.message}", finished_at: Time.current)
    app&.mark_deploy_failed!
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" }) if deploy
    fire_notifications(app.team, "deploy_failed", deploy) if app && deploy
  end

  private

  def resolve_sha(repo, branch)
    sha = IO.popen([ "git", "-C", repo.path, "rev-parse", "refs/heads/#{branch}" ], &:read).to_s.strip
    raise "branch #{branch} not found in the repository" unless sha.match?(/\A[0-9a-f]{40}\z/)
    sha
  end
end
