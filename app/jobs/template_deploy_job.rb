class TemplateDeployJob < ApplicationJob
  queue_as :deploys

  def perform(template_slug:, app_name:, server_id:, user_id:, deploy_id: nil)
    registry = TemplateRegistry.new
    template = registry.find(template_slug)
    raise "Template not found: #{template_slug}" unless template

    server = Server.find(server_id)
    user = User.find(user_id)

    deploy = deploy_id ? Deploy.find(deploy_id) : nil

    if deploy
      deploy.update!(status: :building, started_at: Time.current)
      DeployChannel.broadcast_to(deploy, { type: "log", data: "Starting deployment of #{template[:name]}...\n" })
    end

    deployer = TemplateDeployer.new(
      template: template,
      app_name: app_name,
      server: server,
      user: user,
      on_progress: ->(message) {
        DeployChannel.broadcast_to(deploy, { type: "log", data: "#{message}\n" }) if deploy
      }
    )

    result = deployer.deploy!

    if result[:success]
      app = result[:app]
      if deploy
        deploy.update!(
          app_record: app,
          status: :succeeded,
          log: result[:log].map { |l| l[:step] }.join("\n"),
          finished_at: Time.current
        )
        DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
      end
      Rails.logger.info("TemplateDeployJob: #{template_slug} deployed as #{app_name}")
    else
      if deploy
        deploy.update!(
          status: :failed,
          log: result[:log].map { |l| "#{l[:step]}#{l[:error] ? " — #{l[:error]}" : ""}" }.join("\n"),
          finished_at: Time.current
        )
        DeployChannel.broadcast_to(deploy, { type: "log", data: "\nDeploy failed: #{result[:error]}\n" })
        DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
      end
      Rails.logger.error("TemplateDeployJob: Failed to deploy #{template_slug}: #{result[:error]}")
    end
  end
end
