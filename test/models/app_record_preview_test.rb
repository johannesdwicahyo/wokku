require "test_helper"

class AppRecordPreviewTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "preview-owner@example.com", password: "password123456")
    @team = Team.create!(name: "preview-team", owner: @owner)
    @server = Server.create!(name: "preview-server", host: "10.0.0.3", team: @team)

    @main_app = AppRecord.create!(
      name: "my-app",
      server: @server,
      team: @team,
      creator: @owner,
      is_preview: false
    )

    @preview_app = AppRecord.create!(
      name: "my-app-pr-42",
      server: @server,
      team: @team,
      creator: @owner,
      is_preview: true,
      pr_number: 42,
      parent_app_id: @main_app.id
    )
  end

  # --- Scopes ---

  test "main_apps scope excludes preview apps" do
    main_apps = AppRecord.main_apps
    assert_includes main_apps, @main_app
    assert_not_includes main_apps, @preview_app
  end

  test "previews scope returns only preview apps" do
    previews = AppRecord.previews
    assert_includes previews, @preview_app
    assert_not_includes previews, @main_app
  end

  test "is_preview defaults to false" do
    app = AppRecord.new(name: "new-app", server: @server, team: @team, creator: @owner)
    assert_equal false, app.is_preview
  end

  # --- Associations ---

  test "main app has many preview apps" do
    assert_includes @main_app.preview_apps, @preview_app
  end

  test "preview app belongs to parent app" do
    assert_equal @main_app, @preview_app.parent_app
  end

  test "destroying main app cascades to preview apps" do
    preview_id = @preview_app.id
    @main_app.destroy
    assert_nil AppRecord.find_by(id: preview_id)
  end

  test "preview app stores pr_number" do
    assert_equal 42, @preview_app.pr_number
  end

  test "parent_app is optional (regular apps have no parent)" do
    assert_nil @main_app.parent_app
  end

  # --- Uniqueness index ---

  test "cannot create two preview apps for the same parent and PR number" do
    duplicate = AppRecord.new(
      name: "my-app-pr-42-copy",
      server: @server,
      team: @team,
      creator: @owner,
      is_preview: true,
      pr_number: 42,
      parent_app_id: @main_app.id
    )
    assert_not duplicate.valid?
  end

  test "can have different PR numbers for same parent app" do
    other_preview = AppRecord.new(
      name: "my-app-pr-99",
      server: @server,
      team: @team,
      creator: @owner,
      is_preview: true,
      pr_number: 99,
      parent_app_id: @main_app.id
    )
    assert other_preview.valid?
  end
end
