module Dashboard
  class TemplatesController < BaseController
    include OnboardingTourable
    include PlanEnforceable

    # Bundle v2 (REVISED 2026-05-31): map a template's :min_tier (DynoTier
    # name) to the user-facing box size, so template-deployed apps count
    # against plan.box_quotas the same way new-app form deploys do.
    # Inverse of Plan::BOX_SIZE_TO_DYNO_TIER.
    DYNO_TIER_TO_BOX_SIZE = Plan::BOX_SIZE_TO_DYNO_TIER.invert.freeze

    def index
      registry = TemplateRegistry.new
      @categories = registry.categories
      @servers = policy_scope(Server)

      if params[:q].present?
        @search_results = registry.search(params[:q])
      elsif params[:category].present?
        @category_results = registry.by_category(params[:category])
      else
        @featured = registry.featured
        @category_rows = registry.by_category_with_templates
      end
    end

    def show
      registry = TemplateRegistry.new
      @template = registry.find(params[:id])
      return redirect_to dashboard_templates_path, alert: "Template not found" unless @template
      advance_onboarding_to(2) if @template && @template[:slug] == "astro"
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

      # Bundle v2 (REVISED 2026-05-31): derive box_size from template
      # min_tier so plan.box_quotas applies the same way it does for
      # new-app form deploys. Templates with addons default to "small"
      # (matches the deployer's existing "basic" tier default at line 41
      # of template_deployer.rb); bare templates default to "sleeping".
      box_size = box_size_for_template(template)

      if Addons::SharedProvisioner.feature_enabled?
        begin
          enforce_plan_quota!(current_user, size: box_size, additional: 1)
        rescue PlanEnforceable::PlanQuotaError => e
          return redirect_to dashboard_template_path(params[:template_slug]),
                             alert: "Your plan allows #{e.allowed} #{box_size} boxes — you're at the limit. Upgrade your plan to deploy this template."
        end
      end

      app = AppRecord.create!(
        name: app_name,
        server: server,
        # Apps belong to the *user's* team, not the server's team.
        # wokku.cloud servers are platform infrastructure owned by the
        # admin team; using server.team would put every customer's app
        # under admin's team and hide it from their dashboard.
        team: current_team,
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
      track("template.deployed", target: app, metadata: { template: template[:name] })

      # Onboarding funnel: step-3 advance for Astro template deploys.
      # Uses persistent flash (not flash.now) so the event survives the redirect
      # to the deploy page where _analytics.html.erb will consume it.
      # NOTE: placed BEFORE the first_deploy_started block so that when both
      # conditions apply (tour-active Astro user on their very first app),
      # first_deploy_started is written last and wins the single flash slot —
      # it is the money-path activation event and must not be clobbered.
      if template[:slug] == "astro" && current_user.tour_active?
        current_user.advance_tour_to(3)
        flash[:posthog_event] = "onboarding_tour_step"
        flash[:posthog_props] = { step: 3 }
      end

      # TODO: extract this first-app analytics guard to a shared concern at a 3rd callsite.
      # Activation-funnel "started" signal — fires on the user's first app (generic create has no deploy queued yet; the template path does).
      if current_user.app_records.count == 1
        flash[:posthog_event] = "first_deploy_started"
        flash[:posthog_props] = { template: template[:slug], app: app.name }
      end

      redirect_to dashboard_app_deploy_path(app, deploy), notice: "Deploying #{template[:name]}..."
    end

    private

    # Translate template[:min_tier] (DynoTier name like "basic", "standard")
    # into a box size. Falls back to "small" when the template has addons
    # (mirrors the deployer's default), otherwise "sleeping".
    def box_size_for_template(template)
      tier_name = template[:min_tier].presence ||
                  ((template[:addons] || []).any? ? "basic" : "free")
      DYNO_TIER_TO_BOX_SIZE.fetch(tier_name, "small")
    end

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
