module Dashboard
  class DashboardController < BaseController
    include OnboardingTourable

    def show
      maybe_activate_onboarding!

      if (s = flash[:deploy_template].presence) && TemplateRegistry.new.find(s)
        return redirect_to dashboard_template_path(s, prefill: 1)
      end

      if !session[:fds_sent] &&
         AppRecord.where(team: current_team).joins(:deploys)
                  .where(deploys: { status: :succeeded }).exists?
        flash.now[:posthog_event] = "first_deploy_succeeded"
        session[:fds_sent] = true
      end

      @apps = policy_scope(AppRecord).includes(:server, :domains).order(updated_at: :desc)
      @recent_apps = @apps.limit(6)
      # Collapse consecutive same-action+same-target runs into a single row
      # with a count badge. Without this a chatty deploy session crowds out
      # everything else in the 10-row window.
      raw_activities = Activity.where(team: current_team).order(created_at: :desc).limit(50)
      @activities = []
      raw_activities.each do |a|
        last = @activities.last
        if last && last.action == a.action && last.target_type == a.target_type && last.target_id == a.target_id
          last.singleton_class.attr_accessor :grouped_count unless last.respond_to?(:grouped_count)
          last.grouped_count = (last.grouped_count || 1) + 1
        else
          @activities << a
        end
        break if @activities.size >= 10
      end
      @servers = policy_scope(Server)

      # Month-to-date cost — scoped to the current user's segments so a
      # fresh user sees Rp 0, not the global aggregate. Uses the same
      # ResourceUsage ledger the billing page renders, so the number
      # matches what the user sees on `/dashboard/billing`.
      now = Time.current
      cost_cents = current_user.resource_usages
        .in_period(now.beginning_of_month, now)
        .billable
        .sum { |s| s.cost_cents_in_period(now.beginning_of_month, now) }
      cost_mtd_usd = cost_cents.to_f / 100.0

      @stats = {
        total_apps: @apps.size,
        active: @apps.select(&:running?).size,
        errors: @apps.select(&:crashed?).size,
        cost_mtd: cost_mtd_usd
      }
    end
  end
end
