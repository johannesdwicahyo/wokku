module Push
  # Native iOS push over HTTP/2 with token (.p8) auth. Dark until all four
  # APNS_* values are set: unconfigured = log and skip, never raise.
  class Apns
    REQUIRED = %w[APNS_KEY APNS_KEY_ID APNS_TEAM_ID APNS_BUNDLE_ID].freeze
    DEAD_TOKEN = %w[Unregistered BadDeviceToken].freeze # 410 / 400 from Apple

    def self.configured? = REQUIRED.all? { |k| ENV[k].present? }

    def deliver(tokens, title:, body:, category:, data:)
      return if tokens.empty?
      unless self.class.configured?
        Rails.logger.info("[push] APNs not configured; skipped #{tokens.size} iOS token(s)")
        return
      end

      # ponytail: one connection (one TLS handshake) per alert batch; switch to
      # a pooled long-lived connection if alert volume grows.
      connection = build_connection
      tokens.each do |dt|
        push_one(connection, dt, title:, body:, category:, data:)
      rescue StandardError => e
        # One bad token/key/socket must not abort the batch; never log the token value.
        Rails.logger.warn("[push] APNs error #{e.class} device_token=#{dt.id}")
        Sentry.capture_exception(e, extra: { device_token_id: dt.id }) if defined?(Sentry)
      end
    ensure
      connection&.close
    end

    private

    def build_connection
      options = { auth_method: :token, cert_path: StringIO.new(ENV["APNS_KEY"]),
                  key_id: ENV["APNS_KEY_ID"], team_id: ENV["APNS_TEAM_ID"] }
      if ENV.fetch("APNS_ENVIRONMENT", "production") == "development"
        Apnotic::Connection.development(options)
      else
        Apnotic::Connection.new(options)
      end
    end

    def push_one(connection, device_token, title:, body:, category:, data:)
      n = Apnotic::Notification.new(device_token.token)
      n.topic = ENV["APNS_BUNDLE_ID"]
      n.alert = { title: title, body: body }
      n.sound = "default"
      n.category = category
      n.custom_payload = data
      response = connection.push(n) # nil on timeout
      return if response&.ok?

      payload = response&.body
      reason = payload["reason"] if payload.is_a?(Hash)
      return device_token.destroy if DEAD_TOKEN.include?(reason)

      Rails.logger.warn("[push] APNs failed status=#{response&.status.inspect} reason=#{reason.inspect} device_token=#{device_token.id}")
      Sentry.capture_message("APNs push failed", extra: { status: response&.status, reason: reason, device_token_id: device_token.id }) if defined?(Sentry)
    end
  end
end
