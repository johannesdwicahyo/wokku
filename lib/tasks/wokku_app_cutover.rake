namespace :wokku_app do
  desc "Show the current Wokku-domain cutover state (zone counts + flag)"
  task status: :environment do
    flag = Cloudflare::Dns.wokku_app_enabled? ? "ON" : "OFF"
    canonical = Cloudflare::Dns.canonical_domain
    domains = Cloudflare::Dns.enabled_domains.join(", ")

    puts ""
    puts "  WOKKU_APP_ENABLED  : #{flag}"
    puts "  canonical domain   : #{canonical}"
    puts "  writing to zones   : #{domains}"
    puts ""

    total = AppRecord.count
    return puts("  no AppRecords to evaluate") if total.zero?

    on_cloud = Domain.where("hostname LIKE ?", "%.wokku.cloud").select(:app_record_id).distinct.count
    on_app   = Domain.where("hostname LIKE ?", "%.wokku.app").select(:app_record_id).distinct.count

    puts "  AppRecords        : #{total}"
    puts "  with .wokku.cloud : #{on_cloud}"
    puts "  with .wokku.app   : #{on_app}"
    puts "  pending backfill  : #{total - on_app}"
    puts ""
  end

  desc "Backfill wokku.app DNS records for every existing AppRecord (idempotent; dry-run with DRY=1)"
  task backfill_dns: :environment do
    dry = ENV["DRY"].to_s.downcase.in?(%w[1 true yes on])
    unless Cloudflare::Dns.wokku_app_enabled? || dry
      abort "WOKKU_APP_ENABLED is off and DRY is not set. Set DRY=1 to preview, or flip the flag to run for real."
    end

    puts "[wokku_app:backfill_dns] mode=#{dry ? 'DRY-RUN' : 'LIVE'}"

    apps = AppRecord.includes(:server).where.not(server_id: nil)
    created = updated = skipped = failed = 0
    dns = nil
    dns = Cloudflare::Dns.new(domain: "wokku.app") unless dry

    apps.find_each do |app|
      server = app.server
      next unless server&.host.present?

      hostname = "#{app.name}.wokku.app"
      if dry
        puts "  would ensure  #{hostname.ljust(40)} → #{server.host}"
        created += 1
        next
      end

      begin
        result = dns.create_app_record(app.name, server.host)
        if result
          # Also seed a Domain row so the dashboard shows it.
          app.domains.find_or_create_by!(hostname: hostname)
          created += 1
        end
      rescue Cloudflare::Dns::ApiError => e
        failed += 1
        puts "  ✗ #{hostname}: #{e.message}"
      end
    end

    puts ""
    puts "  processed : #{apps.count}"
    puts "  done      : #{created}"
    puts "  failed    : #{failed}"
    puts ""
    puts "Tip: run `rake wokku_app:status` to see the resulting counts."
  end

  desc "Verify wokku.app zone is reachable + correctly delegated"
  task verify: :environment do
    abort "CLOUDFLARE_ZONE_ID_WOKKU_APP not set" unless ENV["CLOUDFLARE_ZONE_ID_WOKKU_APP"].present?
    info = Cloudflare::Dns.new(domain: "wokku.app").verify!
    puts "  name        : #{info[:name]}"
    puts "  status      : #{info[:status]}"
    puts "  nameservers : #{Array(info[:nameservers]).join(', ')}"
    if info[:status] != "active"
      abort "Zone status is #{info[:status]}, not active. Wait for delegation or check the GoDaddy → Cloudflare NS handoff."
    end
  end
end
