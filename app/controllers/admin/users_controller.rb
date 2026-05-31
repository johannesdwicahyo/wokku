module Admin
  class UsersController < BaseController
    PER_PAGE = 30

    def index
      @query = params[:q].to_s.strip
      scope = User.all
      scope = scope.where("email ILIKE ?", "%#{@query}%") if @query.present?

      # Simple LIMIT/OFFSET pagination (Kaminari not in Gemfile)
      @total = scope.count
      @page  = [ params[:page].to_i, 1 ].max
      @users = scope.order(created_at: :desc)
                    .limit(PER_PAGE)
                    .offset((@page - 1) * PER_PAGE)
      @total_pages = (@total / PER_PAGE.to_f).ceil
    end

    def show
      @target_user = User.find(params[:id])
      @apps        = @target_user.teams.flat_map(&:app_records)
      @databases   = DatabaseService.where(creator_id: @target_user.id)
      @balance     = @target_user.balance_formatted
    end

    # DELETE /admin/users/:id
    # Params:
    #   hard=true  → immediate HardDeleteAccountJob
    #   (default)  → 3-day grace via schedule_deletion!
    def destroy
      @target_user = User.find(params[:id])
      hard = ActiveModel::Type::Boolean.new.cast(params[:hard])

      if hard
        @target_user.admin_hard_delete!(by: current_user)
        Activity.log(
          user: @target_user,
          team: @target_user.teams.first,
          action: "admin.user_hard_deleted",
          metadata: { admin_email: current_user.email, hard: true }
        ) if defined?(Activity)
        redirect_to admin_users_path,
          notice: t("admin.users.deletion_enqueued", default: "Hard delete has been enqueued.")
      else
        @target_user.schedule_deletion!
        Activity.log(
          user: @target_user,
          team: @target_user.teams.first,
          action: "admin.user_deletion_scheduled",
          metadata: { admin_email: current_user.email, hard: false }
        ) if defined?(Activity)
        redirect_to admin_users_path,
          notice: t("admin.users.deletion_scheduled", default: "User has been scheduled for deletion.")
      end
    end
  end
end
