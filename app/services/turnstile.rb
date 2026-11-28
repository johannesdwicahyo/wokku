# Cloudflare Turnstile server-side check (bot check on requesting an email
# sign-in code). Fails closed: a blank token, a network error, a timeout or
# anything but {"success": true} is false.
module Turnstile
  VERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")
  TIMEOUT = 5

  def self.enabled?
    Wokku.config.turnstile_site_key.present? && Wokku.config.turnstile_secret_key.present?
  end

  def self.verify(token:, ip:)
    return false unless token.is_a?(String) && token.present?

    res = Net::HTTP.start(VERIFY_URL.host, VERIFY_URL.port, use_ssl: true,
                          open_timeout: TIMEOUT, read_timeout: TIMEOUT, write_timeout: TIMEOUT) do |http|
      http.post(VERIFY_URL.path, URI.encode_www_form(secret: Wokku.config.turnstile_secret_key, response: token, remoteip: ip),
                "Content-Type" => "application/x-www-form-urlencoded")
    end
    res.is_a?(Net::HTTPSuccess) && JSON.parse(res.body)["success"] == true
  rescue StandardError => e
    Rails.logger.warn "[turnstile] verify failed: #{e.class}"
    false
  end
end
