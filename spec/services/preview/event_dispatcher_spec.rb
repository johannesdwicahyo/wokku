# frozen_string_literal: true

require "rails_helper"

RSpec.describe Preview::EventDispatcher do
  let(:team) { create(:team) }
  let(:user) { create(:user, github_installation_id: 42) }
  let!(:membership) { create(:team_membership, team: team, user: user, role: :admin) }
  let!(:parent) do
    create(:app_record, team: team, name: "myapp",
           github_repo_full_name: "octo/repo",
           git_provider: "github", git_repo_full_name: "octo/repo",
           preview_enabled: true)
  end
  let(:event) do
    Preview::PrEvent.new(provider: :github, action: :opened, pr_number: 7,
                         branch: "feat/x", sha: "abc",
                         repo_full_name: "octo/repo", title: "x",
                         installation_id: 42, author: "u")
  end

  it "enqueues DeployJob for opened PRs when preview_enabled and below cap" do
    expect { described_class.handle(event) }
      .to have_enqueued_job(Preview::DeployJob).with(parent.id, instance_of(Hash))
  end

  it "is no-op when parent has preview_enabled=false" do
    parent.update!(preview_enabled: false)
    expect { described_class.handle(event) }.not_to have_enqueued_job(Preview::DeployJob)
  end

  it "is no-op when no parent matches the repo" do
    parent.update!(github_repo_full_name: "other/repo", git_repo_full_name: "other/repo")
    expect { described_class.handle(event) }.not_to have_enqueued_job(Preview::DeployJob)
  end

  it "is no-op when the parent is itself a preview app (don't recurse)" do
    other_parent = create(:app_record, team: team, github_repo_full_name: "octo/repo", preview_enabled: false)
    create(:app_record, :preview, parent_app: other_parent, pr_number: 99,
           team: team, github_repo_full_name: "octo/repo", preview_enabled: true)
    parent.update!(preview_enabled: false)
    expect { described_class.handle(event) }.not_to have_enqueued_job(Preview::DeployJob)
  end

  it "posts cap-reached comment when at cap, does not enqueue" do
    3.times do |i|
      create(:app_record, :preview, team: team, parent_app: parent, pr_number: i + 100,
             server: parent.server)
    end
    expect(Preview::Commenter).to receive(:cap_reached!).with(parent_app: parent, pr_number: 7)
    expect { described_class.handle(event) }.not_to have_enqueued_job(Preview::DeployJob)
  end

  it "enqueues CleanupJob for closed PRs that have a preview" do
    create(:app_record, :preview, team: team, parent_app: parent, pr_number: 7,
           server: parent.server)
    closed_event = Preview::PrEvent.new(provider: :github, action: :closed, pr_number: 7,
                                        branch: "feat/x", sha: "abc",
                                        repo_full_name: "octo/repo", title: "x",
                                        installation_id: 42, author: "u")
    expect { described_class.handle(closed_event) }
      .to have_enqueued_job(Preview::CleanupJob).with(parent.id, 7)
  end

  it "is no-op for closed PRs with no matching preview" do
    closed_event = Preview::PrEvent.new(provider: :github, action: :closed, pr_number: 999,
                                        branch: "feat/x", sha: "abc",
                                        repo_full_name: "octo/repo", title: "x",
                                        installation_id: 42, author: "u")
    expect { described_class.handle(closed_event) }.not_to have_enqueued_job(Preview::CleanupJob)
  end

  it "looks up parents by (git_provider, git_repo_full_name) for non-github events" do
    parent = create(:app_record, team: team, name: "myapp",
                    git_provider: "gitlab", git_repo_full_name: "octo/repo",
                    preview_enabled: true)
    gitlab_event = Preview::PrEvent.new(provider: :gitlab, action: :opened, pr_number: 7,
                                         branch: "feat/x", sha: "abc",
                                         repo_full_name: "octo/repo", title: "x",
                                         installation_id: nil, author: "u")
    expect { described_class.handle(gitlab_event) }
      .to have_enqueued_job(Preview::DeployJob).with(parent.id, instance_of(Hash))
  end

  it "does NOT match a gitlab event against a github-connected app with the same repo name" do
    create(:app_record, team: team, name: "myapp-github",
           github_repo_full_name: "octo/repo",
           git_provider: "github", git_repo_full_name: "octo/repo",
           preview_enabled: true)
    other_team = create(:team)
    create(:app_record, team: other_team, name: "myapp-gitlab",
           git_provider: "gitlab", git_repo_full_name: "octo/repo",
           preview_enabled: true)
    gitlab_event = Preview::PrEvent.new(provider: :gitlab, action: :opened, pr_number: 7,
                                         branch: "feat/x", sha: "abc",
                                         repo_full_name: "octo/repo", title: "x",
                                         installation_id: nil, author: "u")
    # Only the gitlab-connected app should match.
    expect { described_class.handle(gitlab_event) }
      .to have_enqueued_job(Preview::DeployJob).exactly(1).times
  end
end
