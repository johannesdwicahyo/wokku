# Nightly per-plan prune of the request_aggregates table. Companion to
# RequestAggregateRollupJob (which prunes raw samples). Each app retains
# its bucketed monitor history for `plan.metric_aggregate_retention_days`
# days — the same window we use for metric_hourly.
#
# Aggregates are cheap (1 row per app per 5 min), so retention here is
# generous on every plan.
class RequestAggregateRetentionPruneJob < ApplicationJob
  queue_as :default

  ORPHAN_RETENTION_DAYS = 30

  def perform
    deleted_total = 0
    summary = {}

    app_ids_with_aggs = RequestAggregate.distinct.pluck(:app_record_id)
    AppRecord.where(id: app_ids_with_aggs).includes(creator: :subscriptions).find_each do |app|
      cutoff = app.owner_plan.metric_aggregate_retention_days.days.ago
      deleted = RequestAggregate.where(app_record_id: app.id)
                                .where("bucket_start < ?", cutoff)
                                .delete_all
      next if deleted.zero?

      summary[app.owner_plan.key] = (summary[app.owner_plan.key] || 0) + deleted
      deleted_total += deleted
    end

    Rails.logger.info "RequestAggregateRetentionPruneJob: deleted #{deleted_total} aggregate rows (#{summary})"
    { deleted: deleted_total, by_plan: summary }
  end
end
