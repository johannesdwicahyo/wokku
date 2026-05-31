# Nightly per-plan prune of the logs table. Each app's owner-plan
# defines how many days of logs to retain (`plan.log_retention_days`).
# Orphan rows (no app_record_id — e.g. dokku-postgres system
# containers) fall back to ORPHAN_FALLBACK_DAYS so admins keep enough
# history to debug.
class LogRetentionPruneJob < ApplicationJob
  queue_as :default

  ORPHAN_FALLBACK_DAYS = 30

  def perform
    deleted_total = 0
    summary = {}

    Plan.find_each do |plan|
      cutoff = plan.log_retention_days.days.ago
      app_ids = app_ids_on_plan(plan)
      next if app_ids.empty?

      deleted = Log.where(app_record_id: app_ids).where("ts < ?", cutoff).delete_all
      summary[plan.key] = deleted
      deleted_total += deleted
    end

    orphan_cutoff = ORPHAN_FALLBACK_DAYS.days.ago
    orphan_deleted = Log.where(app_record_id: nil).where("ts < ?", orphan_cutoff).delete_all
    summary["orphan"] = orphan_deleted
    deleted_total += orphan_deleted

    Rails.logger.info "LogRetentionPruneJob: deleted #{deleted_total} rows (#{summary})"
    { deleted: deleted_total, by_plan: summary }
  end

  private

  # All AppRecord ids whose owning user resolves to `plan` via
  # current_plan. The Free plan also catches every app whose owner has
  # no active subscription (since `User#current_plan` falls back to Free).
  def app_ids_on_plan(plan)
    sub_user_ids = User.joins(:subscriptions).merge(Subscription.current)
                       .where(subscriptions: { plan_id: plan.id }).pluck(:id)
    ids = AppRecord.where(created_by_id: sub_user_ids).pluck(:id)
    return ids unless plan.free?

    all_sub_user_ids = User.joins(:subscriptions).merge(Subscription.current).pluck(:id)
    ids += AppRecord.where(created_by_id: nil).pluck(:id)
    ids += AppRecord.where.not(created_by_id: all_sub_user_ids + [ nil ]).pluck(:id)
    ids.uniq
  end
end
