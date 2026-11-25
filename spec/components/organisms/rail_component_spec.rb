# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organisms::RailComponent, type: :component do
  let(:workspace_items) do
    [ { label: "Apps", key: :apps, href: "/dashboard/apps", active: true, count: 6 },
      { label: "Add-ons", key: :databases, href: "/dashboard/databases", active: false } ]
  end
  let(:account_items) { [ { label: "Settings", key: :settings, href: "/dashboard/profile", active: false } ] }
  let(:base) { { workspace_items: workspace_items, account_items: account_items } }

  def render_rail(**opts) = render_inline(described_class.new(**base, **opts))

  it "renders an aside with a labelled nav per group" do
    render_rail
    expect(page).to have_css("aside[aria-label]")
    expect(page).to have_css("nav[aria-label='Workspace']")
    expect(page).to have_css("nav[aria-label='Account']")
    expect(page).to have_css("nav[aria-label='Workspace'] a", text: "Apps")
    expect(page).to have_css("nav[aria-label='Account'] a", text: "Settings")
  end

  it "marks only the active item aria-current and renders counts in mono" do
    render_rail
    expect(page).to have_css("a[aria-current='page']", count: 1, text: "Apps")
    expect(page).to have_css("a span.font-mono", text: "6")
  end

  it "renders the search trigger with a kbd, and omits it when search: false" do
    render_rail
    expect(page).to have_css("button[data-command-menu-open]", text: "Search or run a command")
    expect(page).to have_css("button[data-command-menu-open] kbd", text: "⌘K")
    render_rail(search: false)
    expect(page).not_to have_css("button[data-command-menu-open]")
  end

  it "shows the logo lockup link and no team button without workspaces" do
    render_rail
    expect(page).to have_css("aside a[href='/dashboard'] svg")
    expect(page).not_to have_css("button[aria-haspopup]")
  end

  context "with workspaces" do
    let(:team) { teams(:one) }
    let(:opts) do
      { workspaces: [ teams(:one), teams(:two) ], current_workspace: team,
        workspaces_index_path: "/dashboard/workspaces", workspace_new_path: "/dashboard/workspaces/new" }
    end

    it "renders the team button with mark, name and switcher" do
      render_rail(**opts)
      expect(page).to have_css("button[aria-haspopup] .grid i", count: 9)
      expect(page).to have_text(team.name)
      expect(page).to have_text("Current")
      expect(page).to have_link("+ New workspace", href: "/dashboard/workspaces/new")
      expect(page).to have_link("Manage", href: "/dashboard/workspaces")
    end

    it "truncates a 60-character team name inside min-w-0" do
      long = Team.new(name: "x" * 60).tap { |t| t.id = SecureRandom.uuid }
      render_rail(**opts, workspaces: [ long ], current_workspace: long)
      expect(page).to have_css("button[aria-haspopup] .truncate.min-w-0", text: "x" * 60)
    end

    it "translates the switcher strings" do
      I18n.with_locale(:id) { render_rail(**opts) }
      expect(page).to have_text(I18n.t("console.rail.workspaces", locale: :id))
      expect(page).to have_text(I18n.t("console.rail.current", locale: :id))
      expect(page).not_to have_text("Workspaces")
      expect(page).not_to have_text("+ New workspace")
      expect(page).not_to have_text("Manage")
    end
  end

  describe "#team_mark" do
    subject(:rail) { described_class.new(**base) }

    it "is deterministic, 9 cells, one live" do
      mark = rail.team_mark("abc")
      expect(mark).to eq(rail.team_mark("abc"))
      expect(mark.size).to eq(9)
      expect(mark.count(:live)).to eq(1)
      expect(mark - [ :live ]).to all(satisfy { |c| %i[on off].include?(c) })
    end

    it "varies by seed" do
      marks = %w[a b c d e].map { |s| rail.team_mark(s) }
      expect(marks.uniq.size).to be > 1
    end
  end

  it "renders the footer: locale toggle, user, sign out, version" do
    render_rail(locale: :en, locale_toggle_path: "/locale", user_email: "a@b.c", user_role: "member",
                sign_out_path: "/users/sign_out", version_line: "wokku v9.9")
    expect(page).to have_css("form[action='/locale'] button", text: "EN")
    expect(page).to have_text("a@b.c")
    expect(page).to have_css("a[data-turbo-method='delete'][href='/users/sign_out']", text: "Sign out")
    expect(page).to have_text("wokku v9.9")
  end
end
