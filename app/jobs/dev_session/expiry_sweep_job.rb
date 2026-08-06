class DevSession < ApplicationRecord
  class ExpirySweepJob < ApplicationJob
    queue_as :default

    def perform
      ::DevSession
        .where(revoked_at: nil)
        .where("expires_at <= ?", Time.current)
        .find_each do |session|
          Apps::DevSession::Revoker.new(session).call!
        rescue Apps::DevSession::Error => e
          Sentry.capture_exception(e, extra: { dev_session_id: session.id }) if defined?(Sentry)
        end
    end
  end
end
