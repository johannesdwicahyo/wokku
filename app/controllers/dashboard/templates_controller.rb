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

      TemplateDeployJob.perform_later(
        template_slug: template[:slug],
        app_name: app_name,
        server_id: server.id,
        user_id: current_user.id
      )

      redirect_to dashboard_apps_path, notice: "Deploying #{template[:name]} as '#{app_name}'... This may take a few minutes."
    end
  end
end
