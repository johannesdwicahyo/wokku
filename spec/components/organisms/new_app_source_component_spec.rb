# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::NewAppSourceComponent, type: :component do
  let(:plain) { build_stubbed(:user, github_installation_id: nil) }
  let(:linked) { build_stubbed(:user, github_installation_id: 42) }

  it "offers Connect GitHub plus the public repo URL field without an installation" do
    render_inline(described_class.new(user: plain))
    expect(page).to have_link("Connect GitHub", href: GithubApp.installation_url)
    expect(page).to have_field("app_record[git_repository_url]")
    expect(page).to have_no_css("select[name='github_repo']")
    expect(page).to have_checked_field("source", with: "git", visible: :all)
  end

  it "shows repository and branch selects with an installation, defaulting to github" do
    render_inline(described_class.new(user: linked, repos: %w[acme/web acme/api], repo: "acme/api", branch: "dev"))
    expect(page).to have_checked_field("source", with: "github", visible: :all)
    expect(page).to have_select("github_repo", options: [ "Choose a repository", "acme/web", "acme/api" ], selected: "acme/api")
    expect(page).to have_css("select[name='github_branch'] option[value='dev']")
    expect(page).to have_no_field("app_record[git_repository_url]")
  end

  it "loads repos lazily when none are given" do
    render_inline(described_class.new(user: linked))
    expect(page).to have_css("[data-new-app-target='github'][data-url='#{Rails.application.routes.url_helpers.dashboard_github_repo_list_path}']")
  end

  it "keeps a submitted source and shows the git push hint" do
    render_inline(described_class.new(user: linked, source: "git"))
    expect(page).to have_checked_field("source", with: "git", visible: :all)
    expect(page).to have_text("git push wokku main")
  end

  it "links the template card to the gallery and omits Docker image" do
    render_inline(described_class.new(user: plain))
    expect(page).to have_link(href: Rails.application.routes.url_helpers.dashboard_templates_path, text: "Template")
    expect(page).to have_no_text("Docker image")
    expect(page).to have_css("fieldset legend", text: "Source")
  end

  it "speaks Indonesian" do
    I18n.with_locale(:id) { render_inline(described_class.new(user: plain)) }
    expect(page).to have_text("Hubungkan GitHub")
    expect(page).to have_text("Sumber")
  end
end
