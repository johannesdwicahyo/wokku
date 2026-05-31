module Preview
  class DeployJob < ApplicationJob
    queue_as :deploys

    def perform(parent_app_id, event_attrs)
      parent = AppRecord.find(parent_app_id)
      event  = Preview::PrEvent.new(**event_attrs.symbolize_keys)
      Preview::Deployer.new(parent: parent, event: event).call
    end
  end
end
