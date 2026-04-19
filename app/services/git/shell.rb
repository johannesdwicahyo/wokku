module Git
  # SSH forced-command handler for the wokku.cloud git gateway.
  #
  # Called from bin/wokku-git-shell when a user connects as
  # `git@wokku.cloud`. The gateway's sshd authenticates the client by
  # matching their SSH public key against SshPublicKey records, then
  # forces their shell command to bin/wokku-git-shell, which wraps this
  # service.
  #
  # Responsibilities here (pure logic; no I/O):
  #   - Parse SSH_ORIGINAL_COMMAND
  #   - Validate that the command is a git-receive-pack / git-upload-pack
  #   - Look up the target app and its owning team
  #   - Authorize the connecting SSH key's user for the app
  #
  # The CLI wrapper uses the result of #authorize! to exec an ssh proxy
  # into dokku@<server> with the corresponding git-*-pack command.
  class Shell
    class Error            < StandardError; end
    class UnauthorizedError < Error; end
    class InvalidCommandError < Error; end
    class AppNotFoundError   < Error; end

    ALLOWED_ACTIONS = %i[git-receive-pack git-upload-pack].freeze

    Result = Struct.new(:app, :server, :action, :remote_command, keyword_init: true)

    # @param ssh_key [SshPublicKey] the key that authenticated to the gateway
    # @param ssh_command [String, nil] contents of SSH_ORIGINAL_COMMAND
    def initialize(ssh_key:, ssh_command:)
      @ssh_key = ssh_key
      @ssh_command = ssh_command.to_s
    end

    # Validates everything and returns a Result describing what the CLI
    # wrapper should proxy to. Raises on any policy violation.
    def authorize!
      action, app_name = parse_command

      raise InvalidCommandError, "only git push/pull over SSH is allowed" unless ALLOWED_ACTIONS.include?(action)
      raise InvalidCommandError, "missing app name in #{@ssh_command.inspect}" if app_name.blank?

      app = AppRecord.find_by(name: app_name)
      raise AppNotFoundError, "no app named #{app_name}" unless app

      user = @ssh_key.user
      raise UnauthorizedError, "key is not bound to a user" unless user
      raise UnauthorizedError, "#{user.email} has no access to #{app.name}" unless authorized?(user, app)

      Result.new(
        app: app,
        server: app.server,
        action: action,
        remote_command: "#{action} #{shell_escape(app.name)}"
      )
    end

    # Parse SSH_ORIGINAL_COMMAND forms:
    #   git-receive-pack 'myapp.git'
    #   git-receive-pack 'myapp'
    #   git-upload-pack  "/myapp.git"
    # Returns [action_symbol, app_name] or [nil, nil].
    def parse_command
      return [ nil, nil ] if @ssh_command.empty?

      # Split the command word and the argument. The argument can be quoted
      # with single or double quotes.
      parts = @ssh_command.strip.split(/\s+/, 2)
      return [ nil, nil ] if parts.length != 2

      action = parts[0].to_sym
      return [ nil, nil ] unless ALLOWED_ACTIONS.include?(action)

      arg = parts[1].strip
      # Strip surrounding quotes and leading slash
      arg = arg[1...-1] if arg.start_with?("'", '"') && arg.end_with?(arg[0])
      arg = arg[1..] if arg.start_with?("/")
      # Strip trailing .git
      arg = arg.sub(/\.git\z/, "")

      # App names: lowercase alnum+hyphens, 1-63 chars (matches AppRecord validation)
      return [ action, nil ] unless arg =~ /\A[a-z][a-z0-9-]{0,62}\z/

      [ action, arg ]
    end

    private

    def authorized?(user, app)
      # System admins deploy anywhere. Otherwise the user must be a member
      # of the app's team.
      return true if user.admin?
      app.team.team_memberships.exists?(user_id: user.id)
    end

    def shell_escape(str)
      # Very conservative: only allow the chars we'd already accept in an
      # AppRecord name. We've already validated, but belt-and-braces.
      raise InvalidCommandError, "unsafe app name" unless str =~ /\A[a-z][a-z0-9-]{0,62}\z/
      str
    end
  end
end
