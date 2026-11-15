module Molecules
  class ObjectStorageCardComponent < ApplicationComponent
    def initialize(bucket:)
      @bucket = bucket
    end
    attr_reader :bucket
  end
end
