# Fires 24h after a successful shared→dedicated Redis cutover. Idempotent:
# safe to enqueue more than once; safe to run after the user manually
# destroyed the shared tenant; safe to run after a manual rollback.
# Mirrors DropSharedTenantJob (postgres) — see that file for rationale.
class DropSharedRedisTenantJob < ApplicationJob
  queue_as :default

  def perform(shared_db_id)
    shared = DatabaseService.find_by(id: shared_db_id)
    return :gone           if shared.nil?
    return :still_attached if shared.app_records.exists?
    return :reverted       if shared.status != "pending_destroy"

    slug   = shared.shared_role_name.to_s.sub(/_role\z/, "")
    client = Dokku::Client.new(shared.server)
    Dokku::SharedRedis.new(client).destroy_tenant!(slug: slug)
    shared.destroy!
    :destroyed
  end
end
