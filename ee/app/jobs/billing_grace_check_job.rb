class BillingGraceCheckJob < ApplicationJob
  queue_as :billing

  def perform
    Invoice.overdue.includes(:user).find_each do |invoice|
      user = invoice.user
      days_overdue = (Time.current - invoice.due_date).to_i / 1.day

      if days_overdue >= 7
        # 7+ days overdue: suspend account (stop all apps)
        if user.respond_to?(:billing_status=)
          user.update(billing_status: :suspended)
        end
        user.teams.flat_map(&:app_records).select(&:running?).each do |app|
          begin
            client = Dokku::Client.new(app.server)
            Dokku::Processes.new(client).stop(app.name)
            app.update(status: :stopped)
          rescue => e
            Rails.logger.warn "Failed to stop #{app.name}: #{e.message}"
          end
        end
        Rails.logger.info "Suspended account for user #{user.email} (#{days_overdue} days overdue)"
      elsif days_overdue >= 3
        # 3+ days overdue: grace period warning
        if user.respond_to?(:billing_status=)
          user.update(billing_status: :grace_period)
        end
        Rails.logger.info "Grace period for user #{user.email} (#{days_overdue} days overdue)"
      end
    end
  end
end
