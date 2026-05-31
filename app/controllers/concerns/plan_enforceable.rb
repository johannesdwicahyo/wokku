# OSS no-op stub for PlanEnforceable.
#
# wokku-cloud has historically used a PlanEnforceable concern to gate
# create actions on the Solo/Pro/Team plan quotas (box count, dedicated
# DB slots, etc.). The OSS web UI ships without billing or plans —
# every install is a single-user/single-tenant box where every limit
# would just be infinite. Rather than strip every `include PlanEnforceable`
# from the controllers (which would diverge OSS from wokku-cloud forever),
# we ship a stub that satisfies the include and defines the rescue class
# the controllers reference.

module PlanEnforceable
  extend ActiveSupport::Concern

  # Raised by enforcement helpers; OSS never raises it, but the
  # controllers `rescue_from` the constant so it must exist.
  class PlanQuotaError < StandardError
    attr_reader :requested, :allowed, :size

    def initialize(msg = nil, requested: nil, allowed: nil, size: nil)
      super(msg)
      @requested = requested
      @allowed = allowed
      @size = size
    end
  end

  included do
    # No-op. wokku-cloud overrides this with a before_action chain;
    # OSS lets every request through.
  end
end
