class UpdateAppCdnJob < ApplicationJob
  queue_as :default

  # Toggle the Cloudflare proxy ("orange cloud") for an app's DNS
  # record. Runs async so the controller can respond immediately —
  # the CF API call routinely takes 2-5s and we don't want the user
  # staring at a spinning button.
  def perform(app_id, proxied)
    app = AppRecord.find_by(id: app_id)
    return unless app

    # Flip the proxy on every enabled zone in lockstep so the CDN
    # behavior matches across wokku.cloud + wokku.app.
    Wokku.config.dns_provider.set_proxied!(app.name, proxied: proxied)
    Activity.log(user: app.creator, team: app.team,
                 action: proxied ? "app.cdn_enabled" : "app.cdn_disabled",
                 target: app) rescue nil
  rescue Wokku::Providers::DnsError => e
    Rails.logger.warn("UpdateAppCdnJob failed for #{app&.name}: #{e.message}")
    # Roll back the DB flag so the UI matches reality.
    app&.update(cloudflare_proxied: !proxied)
  end
end
