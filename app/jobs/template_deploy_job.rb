class TemplateDeployJob < ApplicationJob
  queue_as :deploys

  def perform(template_slug:, app_name:, server_id:, user_id:)
    registry = TemplateRegistry.new
    template = registry.find(template_slug)
    raise "Template not found: #{template_slug}" unless template

    server = Server.find(server_id)
    user = User.find(user_id)

    deployer = TemplateDeployer.new(
      template: template,
      app_name: app_name,
      server: server,
      user: user
    )

    result = deployer.deploy!

    if result[:success]
      Rails.logger.info("TemplateDeployJob: #{template_slug} deployed as #{app_name}")
    else
      Rails.logger.error("TemplateDeployJob: Failed to deploy #{template_slug}: #{result[:error]}")
    end
  end
end
