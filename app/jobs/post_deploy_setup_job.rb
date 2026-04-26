class PostDeploySetupJob < ApplicationJob
  queue_as :default

  # Runs after a successful deploy to ensure DNS, SSL, port mapping, domain
  # records, and worker processes are properly configured. Idempotent — safe
  # to run multiple times for the same app.
  def perform(app_id, channel: "git_push")
    app = AppRecord.find_by(id: app_id)
    return unless app
    server = app.server
    client = Dokku::Client.new(server)

    record_release(app, channel)
    assign_default_dyno_tier(app, client)
    setup_dns(app, server)
    setup_domain_record(app)
    setup_ports(app, client)
    setup_ssl(app, client)
    auto_scale_workers(app, client)
  rescue Dokku::Client::ConnectionError => e
    Rails.logger.warn("PostDeploySetupJob: connection failed for #{app.name}: #{e.message}")
  end

  private

  # Git-push deploys go directly through the SSH gateway and never hit
  # DeployJob / GithubDeployJob, so no Release or Activity record exists
  # — which made the UI show "Awaiting Deploy" forever and the activity
  # feed stayed silent. Create them here once we know the push landed.
  def record_release(app, channel)
    # Dedupe: occasionally we see the job run twice for one push (Dokku's
    # git-receive triggering both pre- and post-receive hooks, or client
    # retries). Without this guard the activity feed fills with
    # "deployed batumas" every few ms. If a release was created in the
    # last 30 seconds, skip — same deploy event.
    if app.releases.where("created_at > ?", 30.seconds.ago).exists?
      Rails.logger.info("PostDeploySetupJob: dedupe skip — release just recorded for #{app.name}")
      app.update!(status: :running)
      return
    end

    release = app.releases.create!(description: "Deploy via git push")
    app.update!(status: :running)

    creator = app.creator
    team = app.team
    if creator && team
      Activity.log(
        user: creator, team: team, action: "app.deployed",
        target: app, metadata: { channel: channel, release_id: release.id }
      )
    end
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: release record skipped for #{app.name}: #{e.message}")
  end

  # Git-push deploys skip DeployJob#enforce_resource_limits, so apps
  # created this way had no DynoAllocation and the scaling page showed
  # blank Select buttons. Mirror DeployJob's behavior: ensure a web
  # allocation exists (free tier default) and push the limits to Dokku.
  def assign_default_dyno_tier(app, client)
    allocation = app.dyno_allocations.includes(:dyno_tier).find_by(process_type: "web")
    unless allocation
      free_tier = DynoTier.find_by(name: "free") || DynoTier.order(:price_cents_per_hour).first
      return unless free_tier
      allocation = app.dyno_allocations.create!(process_type: "web", dyno_tier: free_tier, count: 1)
    end

    tier = allocation.dyno_tier
    return unless tier
    resources = Dokku::Resources.new(client)
    resources.apply_limits(app.name, memory_mb: tier.memory_mb, cpu_shares: tier.cpu_shares)
    resources.apply_reservation(app.name, memory_mb: tier.memory_mb)
  rescue StandardError => e
    Rails.logger.warn("PostDeploySetupJob: dyno tier assignment skipped for #{app.name}: #{e.message}")
  end

  # Create Cloudflare DNS record: app-name.wokku.cloud → server IP
  def setup_dns(app, server)
    Cloudflare::Dns.new.create_app_record(app.name, server.host)
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: DNS setup skipped for #{app.name}: #{e.message}")
  end

  # Ensure a Domain record exists in the database for the app's wokku.cloud subdomain
  def setup_domain_record(app)
    hostname = "#{app.name}.wokku.cloud"
    app.domains.find_or_create_by!(hostname: hostname)
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: domain record creation skipped for #{app.name}: #{e.message}")
  end

  # Ensure Dokku has a proper http:80 → container port mapping. Without it
  # nginx never generates a vhost for the app's domains, so the default
  # nginx page serves on every hostname and ACME http-01 challenges 404.
  #
  # Dokku's auto-detection picks the EXPOSEd port from the image. Common
  # values seen in the wild: 3000 (Rails/Node), 5000 (Flask/Python),
  # 8000 (Django/FastAPI), 8080 (Java/Go). When `ports:report` shows the
  # detected port without a matching http:80 mapping (or shows it bound
  # to https on the same port — what Dokku does when the EXPOSE comment
  # hints TLS), rewrite to http:80:<detected>.
  COMMON_CONTAINER_PORTS = %w[3000 5000 8000 8080 4000 80].freeze

  def setup_ports(app, client)
    output = client.run("ports:report #{Shellwords.escape(app.name)}")
    detected = detect_container_port(output)
    return unless detected

    has_http80 = output.match?(/http:80:#{detected}\b/)
    return if has_http80

    client.run("ports:set #{Shellwords.escape(app.name)} http:80:#{detected}")
  rescue Dokku::Client::CommandError => e
    # ports command may not exist on older Dokku — try proxy:ports
    fallback = (defined?(detected) && detected) || "5000"
    begin
      client.run("proxy:ports-set #{Shellwords.escape(app.name)} http:80:#{fallback}")
    rescue => retry_error
      Rails.logger.warn("PostDeploySetupJob: port setup skipped for #{app.name}: #{retry_error.message}")
    end
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: port setup skipped for #{app.name}: #{e.message}")
  end

  # Pull the detected container port from `ports:report` output. Lines look like:
  #   Ports map detected:            https:3000:3000
  #   Ports map:                     http:80:5000
  # Prefer the explicit map; fall back to the detected one. Match against a
  # short whitelist so we don't accidentally rewrite a custom mapping.
  def detect_container_port(report)
    if (m = report.match(/Ports map:\s+\S+:\d+:(\d+)/))
      return m[1] if COMMON_CONTAINER_PORTS.include?(m[1])
    end
    if (m = report.match(/Ports map detected:\s+\S+:\d+:(\d+)/))
      return m[1] if COMMON_CONTAINER_PORTS.include?(m[1])
    end
    nil
  end

  # Enable Let's Encrypt SSL on the app's domain. The plugin needs a global
  # email before it will issue any cert — set it idempotently here so existing
  # servers provisioned before that step was added in the script self-heal on
  # the next deploy.
  def setup_ssl(app, client)
    email = ENV["LETSENCRYPT_EMAIL"].presence || ENV["ADMIN_EMAIL"].presence
    if email
      client.run("letsencrypt:set --global email #{Shellwords.escape(email)}") rescue nil
    end
    Dokku::Domains.new(client).enable_ssl(app.name)
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: SSL setup skipped for #{app.name}: #{e.message}")
  end

  # Detect non-web process types from Dokku and scale them to 1 if at 0
  def auto_scale_workers(app, client)
    output = client.run("ps:scale #{Shellwords.escape(app.name)}")

    # ps:scale output format:
    #   -----> Scaling for superscalper
    #   -----> web=1
    #   -----> worker=0
    scaling_needed = {}
    output.each_line do |line|
      if (match = line.match(/(\w+)=(\d+)/))
        process_type = match[1]
        count = match[2].to_i
        # Auto-scale non-web processes that are at 0
        if process_type != "web" && count == 0
          scaling_needed[process_type] = 1
        end
      end
    end

    if scaling_needed.any?
      Dokku::Processes.new(client).scale(app.name, scaling_needed)
      Rails.logger.info("PostDeploySetupJob: auto-scaled #{app.name}: #{scaling_needed.inspect}")
    end
  rescue => e
    Rails.logger.warn("PostDeploySetupJob: worker auto-scale skipped for #{app.name}: #{e.message}")
  end
end
