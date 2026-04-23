module Dashboard
  class TemplatesController < BaseController
    def index
      registry = TemplateRegistry.new
      @categories = registry.categories
      @templates = if params[:q].present?
        registry.search(params[:q])
      elsif params[:category].present?
        registry.by_category(params[:category])
      else
        registry.all
      end
      @servers = policy_scope(Server)
    end

    def show
      registry = TemplateRegistry.new
      @template = registry.find(params[:id])
      return redirect_to dashboard_templates_path, alert: "Template not found" unless @template
      @servers = policy_scope(Server)
      @suggested_app_name = suggested_app_name(@template[:slug])
      @suggested_server_id = suggested_server_id(@servers)
    end

    def create
      registry = TemplateRegistry.new
      template = registry.find(params[:template_slug])
      return redirect_to dashboard_templates_path, alert: "Template not found" unless template

      server = policy_scope(Server).find(params[:server_id])
      app_name = params[:app_name].to_s.parameterize

      if app_name.blank?
        return redirect_to dashboard_template_path(params[:template_slug]), alert: "App name is required"
      end

      if AppRecord.exists?(name: app_name, server: server)
        return redirect_to dashboard_template_path(params[:template_slug]), alert: "App name already taken on this server"
      end

      app = AppRecord.create!(
        name: app_name,
        server: server,
        team: server.team,
        creator: current_user,
        deploy_branch: "main",
        status: :deploying
      )

      deploy = app.deploys.create!(
        status: :pending
      )

      TemplateDeployJob.perform_later(
        template_slug: template[:slug],
        app_name: app_name,
        server_id: server.id,
        user_id: current_user.id,
        deploy_id: deploy.id
      )
      track("template.deployed", target: app, metadata: { template: template[:name] })

      redirect_to dashboard_app_deploy_path(app, deploy), notice: "Deploying #{template[:name]}..."
    end

    private

    # Pre-fills the app-name field so users don't have to think of one.
    # `<slug>-<random4>` keeps it collision-resistant without looking
    # random-ugly. Users can still edit before submit.
    def suggested_app_name(slug)
      4.times do
        candidate = "#{slug}-#{SecureRandom.alphanumeric(4).downcase}"
        return candidate unless AppRecord.exists?(name: candidate)
      end
      "#{slug}-#{SecureRandom.hex(3)}"
    end

    # Picks a sensible default server:
    #   1. The server the user last deployed to (consistent team placement)
    #   2. Otherwise the first server in the policy scope (sorted by id —
    #      in a launch with one server this is the only choice anyway).
    # Later: swap #2 for geo-nearest once we have server regions +
    # GeoIP on the request.
    def suggested_server_id(servers)
      return nil if servers.blank?
      last = current_user.app_records.order(created_at: :desc).first
      return last.server_id if last && servers.any? { |s| s.id == last.server_id }
      servers.first.id
    end
  end
end
