class TemplateDeployer
  attr_reader :template, :app_name, :server, :user, :log

  def initialize(template:, app_name:, server:, user:)
    @template = template
    @app_name = app_name
    @server = server
    @user = user
    @log = []
  end

  def deploy!
    client = Dokku::Client.new(server)

    step("Creating app #{app_name}...") do
      Dokku::Apps.new(client).create(app_name)
      AppRecord.create!(
        name: app_name,
        server: server,
        team: server.team,
        creator: user,
        deploy_branch: template[:branch] || "main",
        git_repository_url: template[:repo],
        status: :deploying
      )
    end

    app = AppRecord.find_by!(name: app_name, server: server)

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

    app.update!(status: :running)
    @log << { step: "Deploy complete!", at: Time.current }

    { success: true, app: app, log: @log }
  rescue => e
    @log << { step: "Error", message: e.message, at: Time.current }
    app = AppRecord.find_by(name: app_name, server: server)
    app&.update!(status: :crashed)
    { success: false, error: e.message, log: @log }
  end

  def build_steps
    steps = [{ action: :create_app, detail: app_name }]

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
    yield
  rescue => e
    @log << { step: "Failed: #{message}", error: e.message, at: Time.current }
    raise
  end
end
