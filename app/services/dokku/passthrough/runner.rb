require "shellwords"

module Dokku
  module Passthrough
    class Runner
      Result = Struct.new(:ok?, :stdout, :stderr, :exit_code, :duration_ms, :error, :status, keyword_init: true)

      MAX_ARGS       = 32
      MAX_ARG_LENGTH = 256
      TIMEOUT_SECS   = 180
      # Reject shell metacharacters AND control characters (NUL, newline, CR, tab,
      # escape, backslash). Shellwords.shelljoin neutralizes these for shell-injection,
      # but newlines could split args inside dokku's own ForceCommand parser.
      FORBIDDEN_PATTERN = /[;&|`$<>\\\x00-\x1f\x7f]|\$\(|&&|\|\|/

      def self.call(args:, target:, user:, team:, force: false)
        new(args: args, target: target, user: user, team: team, force: force).call
      end

      def initialize(args:, target:, user:, team:, force: false)
        @args   = args
        @target = target
        @user   = user
        @team   = team
        @force  = force
      end

      def call
        err = validate
        return failure(err, status: :unprocessable_entity) if err

        verb = @args.first
        unless Denylist.allow?(verb, @user, force: @force)
          return failure("`#{verb}` is blocked from passthrough. Run as admin with --force, or use the dashboard.",
                         status: :unprocessable_entity)
        end

        execute
      end

      private

      def validate
        return "Missing dokku command. Example: wokku do APP -- ps:list" if !@args.is_a?(Array) || @args.empty?
        return "Too many arguments (max #{MAX_ARGS})" if @args.size > MAX_ARGS
        return "Argument too long (max #{MAX_ARG_LENGTH} chars)" if @args.any? { |a| a.to_s.length > MAX_ARG_LENGTH }
        return "Invalid argument: shell metacharacter not allowed" if @args.any? { |a| a.to_s.match?(FORBIDDEN_PATTERN) }
        nil
      end

      def execute
        server  = @target.is_a?(Server) ? @target : @target.server
        client  = Dokku::Client.new(server)
        command = Shellwords.shelljoin(@args)
        started = Time.current

        begin
          stdout = client.run(command, timeout: TIMEOUT_SECS)
          duration = ((Time.current - started) * 1000).to_i
          log_activity(exit_code: 0, duration_ms: duration)
          Result.new(ok?: true, stdout: stdout, stderr: "", exit_code: 0, duration_ms: duration, error: nil, status: :ok)
        rescue Dokku::Client::CommandError => e
          duration = ((Time.current - started) * 1000).to_i
          log_activity(exit_code: e.exit_code || 1, duration_ms: duration)
          Result.new(ok?: true, stdout: "", stderr: e.stderr.to_s, exit_code: e.exit_code || 1,
                     duration_ms: duration, error: nil, status: :ok)
        rescue Dokku::Client::TimeoutError => e
          failure("Command timed out after #{TIMEOUT_SECS}s. Long-running operations like `rebuild` should use `wokku ps:rebuild`.", status: :gateway_timeout)
        rescue Dokku::Client::ConnectionError => e
          failure(e.message, status: :service_unavailable)
        end
      end

      def log_activity(exit_code:, duration_ms:)
        target = @target.is_a?(Server) ? @target : @target
        Activity.log(
          user: @user, team: @team,
          action: "dokku_passthrough",
          target: target,
          metadata: { args: @args, exit_code: exit_code, duration_ms: duration_ms, forced: @force }
        )
      rescue StandardError
        # Activity logging failure must not break the user-facing call.
      end

      def failure(msg, status:)
        Result.new(ok?: false, stdout: "", stderr: "", exit_code: nil, duration_ms: nil, error: msg, status: status)
      end
    end
  end
end
