class ApplyDynoTierJob < ApplicationJob
  queue_as :default

  def perform(dyno_allocation_id)
    allocation = DynoAllocation.find_by(id: dyno_allocation_id)
    return unless allocation

    app = allocation.app_record
    tier = allocation.dyno_tier
    client = Dokku::Client.new(app.server)
    resources = Dokku::Resources.new(client)

    resources.apply_limits(app.name, memory_mb: tier.memory_mb, cpu_shares: tier.cpu_shares)
    resources.apply_reservation(app.name, memory_mb: tier.memory_mb)
    Dokku::Processes.new(client).scale(app.name, { allocation.process_type => allocation.count })
  end
end
