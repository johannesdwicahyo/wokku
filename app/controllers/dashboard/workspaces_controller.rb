module Dashboard
  # Workspace (Team) management. The switch action sets the session
  # cookie that BaseController#current_team reads. new/create
  # provisions an org team (paid plans only, per the locked decision
  # #4 in project_personal_multi_team_refactor).
  class WorkspacesController < BaseController
    # Only these are selectable for an org workspace — never free, and never
    # a hidden plan like the managed cloud's "usage" (all features, Rp0).
    PAID_PLAN_KEYS = %w[solo pro team].freeze

    def index
      @workspaces = current_user.teams.includes(:plan).order(:created_at)
      # Pre-populate for the inline slide-panel modal so it renders
      # without a round-trip. Standalone /dashboard/workspaces/new still
      # works for direct links.
      @workspace  = Team.new(kind: :org, owner: current_user)
      @paid_plans = Plan.where(key: PAID_PLAN_KEYS).order(:price_idr)
    end

    def show
      @workspace = current_user.teams.find(params[:id])
      @members = @workspace.team_memberships.includes(:user).order(:created_at)
      @is_admin = @workspace.team_memberships.exists?(user: current_user, role: :admin)
      @plan = @workspace.current_plan
      @seats_used     = @members.size
      @seats_included = @plan.seats_included
      @overage_seats  = [ @seats_used - @seats_included, 0 ].max
      # Billing association is cloud-attached (wokku_cloud_billing.rb);
      # a standalone engine has no box addons to show.
      @box_addons     = @workspace.respond_to?(:box_addons) ? @workspace.box_addons.counting : []
    end

    def new
      @workspace = Team.new(kind: :org, owner: current_user)
      @paid_plans = Plan.where(key: PAID_PLAN_KEYS).order(:price_idr)
    end

    def create
      plan = Plan.find_by(id: params.dig(:team, :plan_id))
      return render_form_error("Pick a plan.") if plan.nil?
      return render_form_error("Org workspaces require a paid plan.") unless PAID_PLAN_KEYS.include?(plan.key)

      name = params.dig(:team, :name).to_s.strip
      return render_form_error("Name can't be blank.") if name.empty?

      ActiveRecord::Base.transaction do
        @workspace = Team.create!(
          name: name,
          owner: current_user,
          kind: :org,
          plan: plan,
          slug: unique_slug(name)
        )
        TeamMembership.create!(user: current_user, team: @workspace, role: :admin)
      end

      session[:current_team_id] = @workspace.id
      redirect_to dashboard_root_path, notice: "Workspace #{@workspace.name} created."
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      # teams.name is globally UNIQUE; a taken name would otherwise raise an
      # unhandled RecordInvalid -> generic 422 page. Re-render the form with
      # a clear message so the user just picks another name.
      render_form_error("That workspace name is already taken — try another.")
    end

    def switch
      target = current_user.teams.find_by(id: params[:id])
      return head(:not_found) unless target

      session[:current_team_id] = target.id
      redirect_to(params[:return_to].presence || dashboard_root_path)
    end

    private

    def render_form_error(message)
      @workspace = Team.new(name: params.dig(:team, :name), kind: :org)
      @paid_plans = Plan.where(key: PAID_PLAN_KEYS).order(:price_idr)
      flash.now[:alert] = message
      render :new, status: :unprocessable_entity
    end

    def unique_slug(name)
      base = name.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/(^-|-$)/, "").presence || "workspace"
      candidate = base
      suffix = 1
      while Team.exists?(slug: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end
      candidate
    end
  end
end
