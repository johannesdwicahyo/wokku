module Molecules
  class AppCardComponent < ApplicationComponent
    def initialize(name:, status: :live, updated:, domain:, region: "jkt-1", container: "basic")
      @name = name
      @status = status
      @updated = updated
      @domain = domain
      @region = region
      @container = container
    end
    attr_reader :name, :status, :updated, :domain, :region, :container
  end
end
