# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::ConsoleSidebarComponent, type: :component do
  let(:groups) do
    [
      { label: nil, items: [ { label: "Apps", key: :apps, href: "/dashboard/apps", active: true } ] },
      { label: "Workspace", items: [ { label: "Settings", key: :settings, href: "/dashboard/profile", active: false } ] }
    ]
  end

  it "renders unlabeled and labeled groups" do
    render_inline(described_class.new(groups: groups))
    expect(page).to have_link("Apps", href: "/dashboard/apps")
    expect(page).to have_text("Workspace")
    expect(page).to have_link("Settings", href: "/dashboard/profile")
  end

  it "falls back to the logo when there is no workspace context" do
    render_inline(described_class.new(groups: groups))
    expect(page).to have_css("aside a[href='/']")
  end

  it "renders the workspace switcher when workspaces are present" do
    render_inline(described_class.new(
      groups: groups,
      workspaces: [ teams(:one), teams(:two) ], current_workspace: teams(:one),
      workspaces_index_path: "/dashboard/workspaces", workspace_new_path: "/dashboard/workspaces/new"
    ))
    expect(page).to have_text(teams(:one).name)
    expect(page).to have_text("Current")
    expect(page).to have_link("+ New workspace", href: "/dashboard/workspaces/new")
  end

  it "renders the command-menu trigger when a search url is given" do
    render_inline(described_class.new(groups: groups, search_url: "/dashboard/apps/search", search_placeholder: "search"))
    expect(page).to have_css("button[data-command-menu-open]")
    expect(page).to have_text("⌘K")
  end

  it "renders footer links, user block and version line when given" do
    render_inline(described_class.new(
      groups: groups,
      footer_links: [ { label: "Docs", href: "/docs", external: true } ],
      user_email: "a@b.c", user_role: "member",
      sign_out_path: "/users/sign_out", sign_out_label: "Sign out",
      version_line: "wokku v9.9"
    ))
    expect(page).to have_link("Docs", href: "/docs")
    expect(page).to have_text("a@b.c")
    expect(page).to have_link("Sign out")
    expect(page).to have_text("wokku v9.9")
  end

  it "renders no footer chrome when given none (admin layout)" do
    render_inline(described_class.new(groups: groups))
    expect(page).not_to have_css("[data-controller='theme-toggle'], button[title]")
    expect(page).not_to have_link("Sign out")
  end
end
