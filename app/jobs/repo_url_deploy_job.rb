require "ipaddr"
require "resolv"

# Deploy from a public git repository URL: fetch into the app's own bare
# repo, then build through PushDeployer — the path repo templates and
# GithubDeployJob already take. This is how a self-hoster deploys their own
# code (no git gateway, usually no GitHub App).
#
# The server does the fetch, so the URL must never reach inside: https only,
# the host is resolved ONCE and every address checked, then git is pinned to
# the checked address (http.curloptResolve) with redirects off — it cannot
# re-resolve to an internal host (DNS rebinding) or be redirected to one.
class RepoUrlDeployJob < ApplicationJob
  queue_as :deploys

  BLOCKED_RANGES = %w[0.0.0.0/8 100.64.0.0/10 ::/128].map { |r| IPAddr.new(r) }.freeze

  # => { host:, port:, ip: } for a safe public https URL, else nil.
  def self.resolve_public(url)
    uri = URI.parse(url.to_s)
    return unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?

    host = uri.host.delete_prefix("[").delete_suffix("]")
    return if host.casecmp?("localhost")

    addresses = host.match?(/\A[\d.]+\z|:/) ? [ host ] : Resolv.getaddresses(host)
    return if addresses.empty? || addresses.any? { |a| internal?(a) }

    { host: host, port: uri.port, ip: addresses.first }
  rescue URI::InvalidURIError
    nil
  end

  def self.valid_url?(url) = !resolve_public(url).nil?

  def self.internal?(address)
    ip = IPAddr.new(address)
    ip.loopback? || ip.private? || ip.link_local? || BLOCKED_RANGES.any? { |r| r.include?(ip) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def perform(app_id:, deploy_id:, url:, branch:)
    app = AppRecord.find(app_id)
    deploy = Deploy.find(deploy_id)
    target = self.class.resolve_public(url) or raise ArgumentError, "Repository URL must be a public https:// address"

    repo = Git::BareRepo.new(app.name)
    repo.ensure!
    fetch!(repo, url, branch, target)
    Git::PushDeployer.new(app, sha: resolve_sha(repo, branch), ref: "refs/heads/#{branch}", deploy: deploy).call
  rescue StandardError => e
    deploy&.update!(status: :failed, log: "Could not deploy #{url} (#{branch}): #{e.message}", finished_at: Time.current)
    app&.mark_deploy_failed!
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" }) if deploy
    fire_notifications(app.team, "deploy_failed", deploy) if app && deploy
  end

  private

  def fetch!(repo, url, branch, target)
    ip = target[:ip].include?(":") ? "[#{target[:ip]}]" : target[:ip]
    system("git", "-c", "http.followRedirects=false", "-c", "http.curloptResolve=#{target[:host]}:#{target[:port]}:#{ip}",
           "-C", repo.path, "fetch", "--force", "--quiet", "--", url, "+refs/heads/#{branch}:refs/heads/#{branch}",
           exception: true)
  end

  def resolve_sha(repo, branch)
    sha = IO.popen([ "git", "-C", repo.path, "rev-parse", "refs/heads/#{branch}" ], &:read).to_s.strip
    raise "branch #{branch} not found in the repository" unless sha.match?(/\A[0-9a-f]{40}\z/)
    sha
  end
end
