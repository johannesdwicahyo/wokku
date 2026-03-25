module Api
  module V1
    class TemplatesController < BaseController
      def index
        registry = TemplateRegistry.new
        templates = if params[:q].present?
          registry.search(params[:q])
        elsif params[:category].present?
          registry.by_category(params[:category])
        else
          registry.all
        end
        render json: { templates: templates, categories: registry.categories }
      end

      def show
        registry = TemplateRegistry.new
        template = registry.find(params[:id])
        return render json: { error: "Not found" }, status: :not_found unless template
        render json: template
      end

      def deploy
        registry = TemplateRegistry.new
        template = registry.find(params[:slug])
        return render json: { error: "Template not found" }, status: :not_found unless template

        server = policy_scope(Server).find(params[:server_id])
        app_name = params[:app_name].to_s.parameterize

        return render json: { error: "App name required" }, status: :unprocessable_entity if app_name.blank?

        if AppRecord.exists?(name: app_name, server: server)
          return render json: { error: "App name already taken" }, status: :conflict
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
          status: :pending,
          description: "Template: #{template[:name]}"
        )

        TemplateDeployJob.perform_later(
          template_slug: template[:slug],
          app_name: app_name,
          server_id: server.id,
          user_id: current_user.id,
          deploy_id: deploy.id
        )

        render json: { app: app.as_json(only: [:id, :name, :status]), deploy: deploy.as_json(only: [:id, :status]) }, status: :created
      end
    end
  end
end
