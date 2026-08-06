module Dashboard
  # Team member management — nested under /dashboard/workspaces/:workspace_id.
  # Only admins of the target workspace can add/remove/change roles.
  class TeamMembersController < BaseController
    before_action :set_workspace
    before_action :authorize_admin!

    def create
      email = params.dig(:team_membership, :email).to_s.strip.downcase
      role  = params.dig(:team_membership, :role).presence || "member"

      target = User.find_by("LOWER(email) = ?", email)
      return redirect_with(:alert, "No user with that email — ask them to sign up first.") if target.nil?

      if @workspace.users.include?(target)
        return redirect_with(:notice, "#{target.email} is already in this workspace.")
      end

      return redirect_with(:alert, seat_limit_message) unless seats_available_for_add?

      TeamMembership.create!(user: target, team: @workspace, role: role)
      Activity.log(user: current_user, team: @workspace, action: "team.member_added",
                   target: target, metadata: { channel: "app", email: target.email, role: role })
      redirect_with(:notice, "Added #{target.email} as #{role}.")
    end

    def update
      membership = @workspace.team_memberships.find(params[:id])
      role = params.dig(:team_membership, :role)
      return redirect_with(:alert, "Invalid role.") unless TeamMembership.roles.key?(role)

      # Don't let an admin demote themselves if they're the last admin.
      if membership.user_id == current_user.id && role != "admin" && last_admin?(membership)
        return redirect_with(:alert, "You're the last admin — promote someone else first.")
      end

      membership.update!(role: role)
      redirect_with(:notice, "Role updated to #{role}.")
    end

    def destroy
      membership = @workspace.team_memberships.find(params[:id])
      # Owner can't be removed from their own workspace.
      if membership.user_id == @workspace.owner_id
        return redirect_with(:alert, "Owner can't be removed. Transfer ownership first.")
      end

      removed_email = membership.user.email
      membership.destroy!
      Activity.log(user: current_user, team: @workspace, action: "team.member_removed",
                   target: nil, metadata: { channel: "app", email: removed_email })
      redirect_with(:notice, "Removed #{removed_email}.")
    end

    private

    def set_workspace
      @workspace = current_user.teams.find(params[:workspace_id])
    end

    def authorize_admin!
      ok = @workspace.team_memberships.exists?(user: current_user, role: :admin)
      return if ok
      redirect_to dashboard_workspace_path(@workspace), alert: "Admin-only."
    end

    def seats_available_for_add?
      # Team plan → INFINITY (overage seats billed, no hard cap); other
      # plans hard-cap at seats_included. Encoded in the enforcer.
      @workspace.users.count + 1 <= Wokku.config.plan_enforcer.quota(@workspace, :seats)
    end

    def seat_limit_message
      "Plan includes #{@workspace.current_plan.seats_included} seat" \
      "#{'s' unless @workspace.current_plan.seats_included == 1}. " \
      "Upgrade to the Team plan to add more members (extra seats billed)."
    end

    def last_admin?(membership)
      @workspace.team_memberships.where(role: :admin).where.not(id: membership.id).empty?
    end

    def redirect_with(level, message)
      redirect_to dashboard_workspace_path(@workspace), level => message
    end
  end
end
