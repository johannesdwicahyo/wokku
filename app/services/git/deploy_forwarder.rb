module Git
  class DeployForwarder
    def initialize(user, app_name)
      @user = user
      @app_name = app_name
    end

    def forward
      app = AppRecord.find_by!(name: @app_name)
      policy = AppRecordPolicy.new(@user, app)
      raise Pundit::NotAuthorizedError unless policy.update?

      release = app.releases.create!(description: "Deploy via git push")
      deploy = app.deploys.create!(release: release, status: :pending)

      client = Dokku::Client.new(app.server)
      deploy.update!(status: :building, started_at: Time.current)

      log = +""
      client.run_streaming("-- git-receive-pack '#{app.name}'") do |data|
        log << data
        DeployChannel.broadcast_to(deploy, { type: "log", data: data })
      end

      deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
      app.update!(status: :running)
    rescue StandardError => e
      deploy&.update(status: :failed, log: "#{log}\n#{e.message}", finished_at: Time.current)
      raise
    end
  end
end
