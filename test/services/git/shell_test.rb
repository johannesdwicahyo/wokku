require "test_helper"

class Git::ShellTest < ActiveSupport::TestCase
  setup do
    @team = teams(:one)
    @user = users(:one) # member of team one
    @server = servers(:one)
    @app = app_records(:one) # in team one, on server one
    @key = @user.ssh_public_keys.create!(
      name: "laptop",
      public_key: "ssh-ed25519 AAAAfake user@host",
      fingerprint: "SHA256:#{SecureRandom.hex(8)}"
    )
  end

  def shell(command, key: @key)
    Git::Shell.new(ssh_key: key, ssh_command: command)
  end

  # ---------------------------------------------------------------------------
  # Parsing
  # ---------------------------------------------------------------------------

  test "parses git-receive-pack with single-quoted .git arg" do
    action, app = shell("git-receive-pack 'myapp.git'").parse_command
    assert_equal :"git-receive-pack", action
    assert_equal "myapp", app
  end

  test "parses git-upload-pack without quotes" do
    action, app = shell("git-upload-pack my-cool-app").parse_command
    assert_equal :"git-upload-pack", action
    assert_equal "my-cool-app", app
  end

  test "strips leading slash in the app arg" do
    action, app = shell("git-receive-pack '/myapp.git'").parse_command
    assert_equal :"git-receive-pack", action
    assert_equal "myapp", app
  end

  test "rejects non-git command" do
    action, app = shell("ls /etc").parse_command
    assert_nil action
    assert_nil app
  end

  test "rejects empty command" do
    action, app = shell("").parse_command
    assert_nil action
    assert_nil app
  end

  test "rejects app name with shell metacharacters" do
    _, app = shell("git-receive-pack 'myapp;rm -rf /'").parse_command
    assert_nil app
  end

  test "rejects app name starting with a digit" do
    _, app = shell("git-receive-pack '1myapp'").parse_command
    assert_nil app
  end

  # ---------------------------------------------------------------------------
  # Authorization — happy paths
  # ---------------------------------------------------------------------------

  test "authorizes team member for receive-pack on team app" do
    result = shell("git-receive-pack '#{@app.name}.git'").authorize!
    assert_equal @app, result.app
    assert_equal @app.server, result.server
    assert_equal :"git-receive-pack", result.action
    assert_equal "git-receive-pack #{@app.name}", result.remote_command
  end

  test "authorizes team member for upload-pack too (git pull)" do
    result = shell("git-upload-pack '#{@app.name}.git'").authorize!
    assert_equal :"git-upload-pack", result.action
    assert_equal "git-upload-pack #{@app.name}", result.remote_command
  end

  test "authorizes system admin for an app on any team" do
    admin = users(:admin)
    admin_key = admin.ssh_public_keys.create!(
      name: "admin-laptop",
      public_key: "ssh-ed25519 AAAAfake2 admin@host",
      fingerprint: "SHA256:#{SecureRandom.hex(8)}"
    )
    # Use app_records(:two) which belongs to team two, where :admin isn't a member
    other_team_app = app_records(:two)
    result = shell("git-receive-pack '#{other_team_app.name}.git'", key: admin_key).authorize!
    assert_equal other_team_app, result.app
  end

  # ---------------------------------------------------------------------------
  # Authorization — rejections
  # ---------------------------------------------------------------------------

  test "rejects non-member of the app's team" do
    outsider = User.create!(email: "outsider@example.com", password: "password123456")
    outsider_key = outsider.ssh_public_keys.create!(
      name: "outsider-laptop",
      public_key: "ssh-ed25519 AAAAfake3 outsider@host",
      fingerprint: "SHA256:#{SecureRandom.hex(8)}"
    )
    other_team_app = app_records(:two)
    err = assert_raises(Git::Shell::UnauthorizedError) do
      shell("git-receive-pack '#{other_team_app.name}.git'", key: outsider_key).authorize!
    end
    assert_match(/no access/, err.message)
  end

  test "rejects when app does not exist" do
    err = assert_raises(Git::Shell::AppNotFoundError) do
      shell("git-receive-pack 'nonexistent-app.git'").authorize!
    end
    assert_match(/no app named/, err.message)
  end

  test "rejects interactive / empty command" do
    err = assert_raises(Git::Shell::InvalidCommandError) do
      shell("").authorize!
    end
    assert_match(/only git push/, err.message)
  end

  test "rejects arbitrary shell command" do
    assert_raises(Git::Shell::InvalidCommandError) do
      shell("ls -la /etc").authorize!
    end
  end

  test "rejects when key is not bound to a user" do
    @key.define_singleton_method(:user) { nil }
    err = assert_raises(Git::Shell::UnauthorizedError) do
      shell("git-receive-pack '#{@app.name}.git'", key: @key).authorize!
    end
    assert_match(/not bound to a user/, err.message)
  end
end
