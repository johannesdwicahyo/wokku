# app/models/lifecycle_op.rb — mirrors ServiceOp (service_op.rb)
class LifecycleOp < ApplicationRecord
  KINDS = %w[stack.converge stack.remove stack.run registry.prune].freeze
  belongs_to :app_record
  belongs_to :server
  enum :status, { pending: 0, claimed: 1, succeeded: 2, failed: 3 }
  validates :kind, inclusion: { in: KINDS }
  def terminal? = succeeded? || failed?

  # Per-service env copies (params["services"][proc]["env"]) are secrets at
  # rest that nothing reads back — converge re-assembles env from EnvVar rows.
  def self.scrub_service_env(params)
    services = params.to_h["services"]
    return params unless services.is_a?(Hash)
    params.merge("services" => services.transform_values { |s| s.is_a?(Hash) && s.key?("env") ? s.merge("env" => "[REDACTED]") : s })
  end
end
