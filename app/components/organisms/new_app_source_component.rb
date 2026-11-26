# frozen_string_literal: true

module Organisms
  # Create form section 01. Radio group `source`: github / git / template.
  # The Docker image card from the mockup is omitted on purpose: no backend path.
  # `repos:` (array of "owner/name") pre-renders the repo select; nil = the page
  # controller fetches Dashboard::GithubController#list lazily. The selected_*
  # kwargs let a 422 re-render keep every choice.
  class NewAppSourceComponent < ApplicationComponent
    CARD = "relative flex flex-col gap-1 border border-line bg-paper rounded-md p-3 cursor-pointer " \
           "has-[:checked]:border-live has-[:checked]:bg-accent-soft has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-live"
    LABEL = "block font-mono text-[11px] uppercase tracking-[.12em] text-muted mb-1.5"
    FIELD = "w-full bg-paper border border-dark-line rounded-md px-3 py-2 text-sm text-ink"

    def initialize(user:, repos: nil, repos_error: false, source: nil, repo: nil, branch: nil, repo_url: nil)
      @user, @repos, @repos_error, @repo, @branch, @repo_url = user, repos, repos_error, repo, branch, repo_url
      @source = source.presence&.to_s || (installed? ? "github" : "git")
    end
    attr_reader :repos, :repos_error, :repo, :branch, :repo_url, :source

    def installed? = @user.github_installation_id.present?
    def checked?(key) = source == key
    def connect_url = GithubApp.installation_url
    def lazy_url = helpers.dashboard_github_repo_list_path
  end
end
