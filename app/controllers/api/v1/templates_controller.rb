module Api
  module V1
    class TemplatesController < BaseController
      include PlanEnforceable

      # Mirror Dashboard::TemplatesController::DYNO_TIER_TO_BOX_SIZE so the
      # API path counts against plan.box_quotas the same way the dashboard
      # path does. Bundle v2 (REVISED 2026-05-31).
      DYNO_TIER_TO_BOX_SIZE = DynoTier::BOX_SIZE_TO_DYNO_TIER.invert.freeze

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
        return render_api_error(:not_found, message: "Not found") unless template
        render json: template
      end

      def deploy
        registry = TemplateRegistry.new
        template = registry.find(params[:slug])
        return render_api_error(:not_found, message: "Template not found") unless template

        server = Server.lookup!(params[:server_id])
        # The CLI and MCP send `name`; the documented param is `app_name`.
        app_name = (params[:app_name].presence || params[:name]).to_s.parameterize

        return render json: { error: "App name required" }, status: :unprocessable_entity if app_name.blank?

        if AppRecord.exists?(name: app_name, server: server)
          return render_api_error(:already_exists, message: "App name already taken")
        end

        box_size = resolve_box_size(current_user, required: box_size_for_template(template))

        if Addons::SharedProvisioner.feature_enabled?
          begin
            enforce_plan_quota!(current_user, size: box_size, additional: 1)
          rescue PlanEnforceable::PlanQuotaError => e
            msg = e.is_a?(PlanEnforceable::AccountLimitError) ? e.message : "Plan allows #{e.allowed} #{box_size} boxes — at limit. Upgrade your plan."
            return render json: { error: msg },
                          status: :forbidden
          end
        end

        # Builder mode: plan limit + capacity before anything is created.
        preflight = TemplateDeployer.new(template: template, app_name: app_name, server: server, user: current_user)
                                    .builder_preflight(AppRecord.new(team: current_user.teams.first, box_size: box_size))
        return render_api_error(:invalid_params, message: preflight.error, status: :unprocessable_entity) unless preflight.ok

        app = AppRecord.create!(
          name: app_name,
          server: server,
          # See comment in template_deployer.rb — server.team is the
          # platform admin team, not the customer's team.
          team: current_user.teams.first,
          creator: current_user,
          deploy_branch: "main",
          status: :deploying,
          box_size: box_size
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

        render json: { app: app.as_json(only: [ :id, :name, :status, :box_size ]), deploy: deploy.as_json(only: [ :id, :status ]) }, status: :created
      end

      private

      # Same logic as Dashboard::TemplatesController#box_size_for_template.
      # Translate template[:min_tier] (DynoTier name) into a box size.
      def box_size_for_template(template)
        tier_name = template[:min_tier].presence ||
                    ((template[:addons] || []).any? ? "basic" : "free")
        DYNO_TIER_TO_BOX_SIZE.fetch(tier_name, "small")
      end
    end
  end
end
