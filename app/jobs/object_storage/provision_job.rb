module ObjectStorage
  class ProvisionJob < ApplicationJob
    queue_as :default
    retry_on ObjectStorage::Error, wait: :polynomially_longer, attempts: 3

    def perform(bucket_id)
      bucket = ObjectStorageBucket.find_by(id: bucket_id)
      Provisioner.provision!(bucket) if bucket
    end
  end
end
