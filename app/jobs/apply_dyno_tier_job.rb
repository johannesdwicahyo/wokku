# Jobs enqueued before the per-resource deploy carry a DynoAllocation id.
# Delete in P4 cleanup.
class ApplyDynoTierJob < ApplicationJob
  queue_as :default
  def perform(dyno_allocation_id)
    app_id = DynoAllocation.where(id: dyno_allocation_id).pick(:app_record_id)
    ApplyResourcesJob.perform_now(app_id) if app_id
  end
end
