module ObjectStorage
  class DeprovisionJob < ApplicationJob
    queue_as :default
    retry_on ObjectStorage::Error, wait: :polynomially_longer, attempts: 5

    def perform(bucket_id)
      bucket = ObjectStorageBucket.find_by(id: bucket_id)
      Provisioner.destroy!(bucket) if bucket
    end
  end
end
