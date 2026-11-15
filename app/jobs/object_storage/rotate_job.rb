module ObjectStorage
  class RotateJob < ApplicationJob
    queue_as :default
    retry_on ObjectStorage::Error, wait: :polynomially_longer, attempts: 3

    def perform(bucket_id)
      bucket = ObjectStorageBucket.find_by(id: bucket_id)
      Provisioner.rotate!(bucket) if bucket&.active?
    end
  end
end
