# One imperative datastore operation for wokkud (Track B Phase B4).
# Same shape as the Phase 4c build pipeline: pending ids piggyback on
# heartbeats; wokkud claims, streams log, reports a typed result.
class ServiceOp < ApplicationRecord
  KINDS = %w[
    service.create service.adopt service.start service.stop service.restart
    service.destroy service.set_limits service.export service.import
    service.ensure
    tenant.provision tenant.destroy tenant.set_quota service.check_quotas
  ].freeze

  belongs_to :database_service
  belongs_to :server

  enum :status, { pending: 0, claimed: 1, succeeded: 2, failed: 3 }

  validates :kind, inclusion: { in: KINDS }

  def terminal? = succeeded? || failed?
end
