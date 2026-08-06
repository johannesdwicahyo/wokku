# Fires 24h after a successful shared→dedicated Redis cutover. The logic is
# fully engine-agnostic since W7 Phase 3 (tenant.destroy op on the parent) —
# this subclass only preserves the job identity already-enqueued 24h timers
# were serialized under.
class DropSharedRedisTenantJob < DropSharedTenantJob
end
