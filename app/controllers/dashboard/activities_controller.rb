module Dashboard
  class ActivitiesController < BaseController
    PER_PAGE = 50

    def index
      @filters = filter_params
      @page = [ params[:page].to_i, 1 ].max
      @per_page = PER_PAGE
      base = filtered_scope.includes(:user)
      records = base.offset((@page - 1) * @per_page).limit(@per_page + 1).to_a
      @has_more = records.size > @per_page
      @activities = records.first(@per_page)
      @team_users = current_team.users.order(:email).pluck(:id, :email)
      @actions    = Activity::ACTIONS.keys.sort
      @channels   = Activity::CHANNELS
      @latest_digest = ActivityDigest.order(date: :desc).first

      respond_to do |format|
        format.html
        format.csv do
          send_data activities_csv(filtered_scope.includes(:user).ordered),
                    filename: "wokku-activity-#{Date.current.iso8601}.csv"
        end
      end
    end

    private

    def filter_params
      params.permit(:action_eq, :user_id, :channel, :since, :until)
    end

    def filtered_scope
      since_at = parse_time(@filters[:since])
      until_at = parse_time(@filters[:until], end_of_day: true)
      Activity.for_team(current_team)
              .with_action(@filters[:action_eq])
              .with_user(@filters[:user_id])
              .with_channel(@filters[:channel])
              .since(since_at)
              .until_(until_at)
              .ordered
    end

    def parse_time(raw, end_of_day: false)
      return nil if raw.blank?
      t = Time.zone.parse(raw)
      end_of_day ? t.end_of_day : t
    rescue ArgumentError
      nil
    end

    def activities_csv(scope)
      require "csv"
      CSV.generate do |csv|
        csv << %w[created_at user_email action target_type target_name channel metadata_json]
        scope.find_each do |a|
          csv << [
            a.created_at.iso8601,
            a.user.email,
            a.action,
            a.target_type,
            a.target_name,
            (a.metadata || {}).with_indifferent_access[:channel],
            (a.metadata || {}).to_json
          ]
        end
      end
    end
  end
end
