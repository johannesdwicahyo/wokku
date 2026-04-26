# Regenerates /etc/wokku/git-authorized-keys on the host whenever an
# SshPublicKey is added or removed. A no-op if the path env var isn't
# configured (dev/test), so it's safe to enqueue unconditionally.
class UpdateGatewayAuthorizedKeysJob < ApplicationJob
  queue_as :default

  def perform
    Git::AuthorizedKeysWriter.write!
  rescue StandardError => e
    Rails.logger.error("UpdateGatewayAuthorizedKeysJob: #{e.class}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
