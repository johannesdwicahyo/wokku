# Recurring entrypoint (config/recurring.yml) → enqueues the sweep.
# Mirrors ReconcileAppStatusesSchedulerJob's enqueue mechanics (queue_as
# :health, perform_later); no per-server fan-out here since
# DatastoreReconcileJob takes no args — it sweeps all container-owning
# services itself.
class DatastoreReconcileSchedulerJob < ApplicationJob
  queue_as :health

  def perform
    DatastoreReconcileJob.perform_later
  end
end
