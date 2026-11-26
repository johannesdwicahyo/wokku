module Organisms
  # Header of the app detail page: status + name + addresses on the left,
  # Restart / Roll back / Deploy / ⋯ on the right (members only).
  # `releases` is the controller's recent releases, newest first, includes(:deploy).
  class AppHeaderComponent < ApplicationComponent
    def initialize(app:, releases:, can_update:)
      @app = app
      @releases = releases.to_a
      @can_update = can_update
    end
    attr_reader :app, :releases, :can_update

    def github? = app.github_repo_full_name.present?
    def branch = app.deploy_branch.presence || "main"
    def show_deploy? = github? && !app.deploy_locked_at?
    def running? = app.status.to_s != "stopped"

    # Custom domains first, then the platform address. Wildcards aren't links.
    def hostnames
      custom = app.domains.reject { |d| d.wildcard? || d.managed_subdomain? }.map(&:hostname).sort
      custom + [ self.class.platform_address(app) ]
    end

    def self.platform_address(app) = "#{app.name}.#{Wokku.config.canonical_domain}"

    # Newest release whose deploy succeeded (same rule as ReleasesController#index).
    def self.current_release(releases) = releases.find { |r| r.deploy&.succeeded? }

    # Newest succeeded, non-current release with a recorded artifact.
    def rollback_target
      return @rollback_target if defined?(@rollback_target)
      current = self.class.current_release(releases)
      @rollback_target = releases.find do |r|
        r != current && r.deploy&.succeeded? && RollbackArtifactResolver.recorded?(r.deploy)
      end
    end
  end
end
