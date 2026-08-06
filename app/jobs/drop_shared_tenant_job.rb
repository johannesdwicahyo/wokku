# Fires 24h after a successful shared→dedicated cutover. Idempotent:
# safe to enqueue more than once; safe to run after the user manually
# destroyed the shared tenant; safe to run after a manual rollback.
#
# W7 Phase 3: the host teardown is a tenant.destroy op on the shared PARENT
# (C1 contract: op.service is the parent container, the slug travels in
# params). wokkud's drops are not-found tolerant (IF EXISTS / DELUSER-0),
# so an already-gone tenant still reports success; any other failure raises
# and the job surfaces it. Engine-agnostic — DropSharedRedisTenantJob
# subclasses this for its own queue identity.
class DropSharedTenantJob < ApplicationJob
  queue_as :default

  def perform(shared_db_id)
    shared = DatabaseService.find_by(id: shared_db_id)
    return :gone           if shared.nil?
    return :still_attached if shared.app_records.exists?
    return :reverted       if shared.status != "pending_destroy"

    if (parent = shared.parent_service)
      Services::Ops.issue_and_wait!(
        service: parent, kind: "tenant.destroy",
        params: { slug: DatabaseProvisioner.shared_tenant_slug(shared), force: true }
      )
    end
    shared.destroy!
    :destroyed
  end
end
