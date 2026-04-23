class TemplateDeployer
  attr_reader :template, :app_name, :server, :user, :log

  def initialize(template:, app_name:, server:, user:, on_progress: nil)
    @template = template
    @app_name = app_name
    @server = server
    @user = user
    @on_progress = on_progress
    @log = []
  end

  def deploy!
    client = Dokku::Client.new(server)

    step("Creating app #{app_name}...") do
      Dokku::Apps.new(client).create(app_name)
      AppRecord.find_or_initialize_by(name: app_name, server: server).tap do |a|
        a.assign_attributes(
          team: server.team,
          creator: user,
          deploy_branch: template[:branch] || "main",
          git_repository_url: template[:repo],
          status: :deploying
        )
        a.save!
      end
    end

    app = AppRecord.find_by!(name: app_name, server: server)

    # Assign free tier and enforce resource limits so no app runs unrestricted
    step("Setting resource limits...") do
      free_tier = DynoTier.find_by(name: "free") || DynoTier.order(:price_cents_per_hour).first
      if free_tier
        allocation = app.dyno_allocations.find_or_create_by!(process_type: "web") do |a|
          a.dyno_tier = free_tier
          a.count = 1
        end
        resources = Dokku::Resources.new(client)
        resources.apply_limits(app_name, memory_mb: free_tier.memory_mb, cpu_shares: free_tier.cpu_shares)
        resources.apply_reservation(app_name, memory_mb: free_tier.memory_mb)
      end
    end

    (template[:addons] || []).each do |addon|
      step("Provisioning #{addon['type']}...") do
        db_name = "#{app_name}-#{addon['type']}"
        Dokku::Databases.new(client).create(addon["type"], db_name)
        Dokku::Databases.new(client).link(addon["type"], db_name, app_name)
        DatabaseService.create!(
          name: db_name,
          service_type: addon["type"],
          server: server,
          status: :running
        )
        AppDatabase.create!(
          app_record: app,
          database_service: DatabaseService.find_by!(name: db_name, server: server),
          alias_name: db_name
        )
      end
    end

    if template[:env].present?
      step("Setting environment variables...") do
        Dokku::Config.new(client).set(app_name, template[:env])
        template[:env].each do |key, value|
          app.env_vars.find_or_create_by!(key: key) { |ev| ev.value = value }
        end
      end
    end

    if template[:postgres_components]
      step("Expanding DATABASE_URL into DB_POSTGRESDB_* components...") do
        expand_postgres_components!(client, app, app_name)
      end
    end

    if template[:deploy_method] == "docker_image" && template[:docker_image].present?
      # Set port mapping before deploying (Docker images often expose non-standard ports)
      container_port = template[:container_port] || 3000
      step("Configuring port mapping (80 → #{container_port})...") do
        client.run("ports:set #{app_name} http:80:#{container_port}")
      end

      step("Deploying Docker image #{template[:docker_image]}...") do
        client.run("git:from-image #{app_name} #{template[:docker_image]}", timeout: 300)
      end

      # Enable Let's Encrypt SSL
      step("Enabling SSL...") do
        client.run("letsencrypt:enable #{app_name}", timeout: 120)
      rescue Dokku::Client::CommandError => e
        @log << { step: "SSL setup skipped: #{e.message}", at: Time.current }
      end
    else
      step("Cloning #{template[:repo]} and deploying...") do
        begin
          client.run(
            "git:sync --build #{app_name} #{template[:repo]} #{template[:branch] || 'main'}",
            timeout: 300
          )
        rescue Dokku::Client::CommandError => e
          raise unless e.message.include?("is not a dokku command")
          client.run("git:from-url #{app_name} #{template[:repo]}", timeout: 300)
        end
      end
    end

    if template[:post_deploy].present?
      step("Running post-deploy: #{template[:post_deploy]}") do
        client.run("run #{app_name} #{template[:post_deploy]}", timeout: 120)
      end
    end

    # Create DNS record: app-name.wokku.cloud → server IP
    step("Configuring DNS...") do
      Cloudflare::Dns.new.create_app_record(app_name, server.host)
    rescue => e
      @log << { step: "DNS setup skipped: #{e.message}", at: Time.current }
    end

    app.update!(status: :running)
    @log << { step: "Deploy complete!", at: Time.current }
    @on_progress&.call("Deploy complete!")

    { success: true, app: app, log: @log }
  rescue => e
    @log << { step: "Error", message: e.message, at: Time.current }
    @on_progress&.call("Deploy failed: #{e.message}. Rolling back...")
    rollback_partial_deploy!(e)
    { success: false, error: e.message, log: @log }
  end

  # Clean up any partially-created resources when a deploy step fails.
  # This prevents users from being stuck with half-configured apps and orphaned
  # databases that continue to consume server resources.
  def rollback_partial_deploy!(original_error)
    client = Dokku::Client.new(server)
    app = AppRecord.find_by(name: app_name, server: server)
    return unless app

    # Tear down any databases that were created for this app
    begin
      app.app_databases.includes(:database_service).each do |ad|
        db = ad.database_service
        next unless db
        begin
          Dokku::Databases.new(client).unlink(db.service_type, db.name, app_name) rescue nil
          Dokku::Databases.new(client).destroy(db.service_type, db.name) rescue nil
          db.destroy
        rescue StandardError => e
          @log << { step: "Rollback warning: could not clean up database #{db.name}", error: e.message, at: Time.current }
        end
      end

      # Clean up DNS record
      Cloudflare::Dns.new.delete_app_record(app_name) rescue nil

      # Destroy the Dokku app
      Dokku::Apps.new(client).destroy(app_name) rescue nil

      # Remove the Rails record
      app.destroy
      @log << { step: "Rollback complete. Partial resources removed.", at: Time.current }
    rescue StandardError => rollback_error
      # If cleanup itself fails, at least leave the app in a crashed state so
      # the user sees something went wrong.
      app.update!(status: :crashed)
      @log << { step: "Rollback failed", error: rollback_error.message, at: Time.current }
      Rails.logger.error("TemplateDeployer rollback failed: #{rollback_error.message} (original: #{original_error.message})")
    end
  end

  def build_steps
    steps = [ { action: :create_app, detail: app_name } ]

    (template[:addons] || []).each do |addon|
      steps << { action: :provision_addon, detail: addon }
    end

    steps << { action: :set_env, detail: template[:env] } if template[:env].present?
    steps << { action: :deploy, detail: template[:repo] }
    steps << { action: :post_deploy, detail: template[:post_deploy] } if template[:post_deploy].present?

    steps
  end

  private

  def step(message)
    @log << { step: message, at: Time.current }
    @on_progress&.call(message)
    yield
  rescue => e
    @log << { step: "Failed: #{message}", error: e.message, at: Time.current }
    @on_progress&.call("FAILED: #{message} — #{e.message}")
    raise
  end

  # Some apps (n8n, strapi, keycloak) don't accept DATABASE_URL — they
  # want DB_POSTGRESDB_HOST, DB_POSTGRESDB_PORT, etc. as separate vars.
  # Dokku's postgres plugin only exposes DATABASE_URL, so after linking
  # we parse it and set the component vars explicitly.
  def expand_postgres_components!(client, app, app_name)
    database_url = Dokku::Config.new(client).get(app_name, "DATABASE_URL")
    return if database_url.blank?

    uri = URI.parse(database_url)
    components = {
      "DB_POSTGRESDB_HOST"     => uri.host,
      "DB_POSTGRESDB_PORT"     => (uri.port || 5432).to_s,
      "DB_POSTGRESDB_DATABASE" => uri.path.to_s.sub(%r{\A/}, ""),
      "DB_POSTGRESDB_USER"     => uri.user.to_s,
      "DB_POSTGRESDB_PASSWORD" => URI.decode_www_form_component(uri.password.to_s)
    }
    Dokku::Config.new(client).set(app_name, components)
    components.each do |key, value|
      app.env_vars.find_or_create_by!(key: key) { |ev| ev.value = value }
    end
  end
end
