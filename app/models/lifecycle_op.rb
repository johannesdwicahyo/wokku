# app/models/lifecycle_op.rb — mirrors ServiceOp (service_op.rb)
class LifecycleOp < ApplicationRecord
  KINDS = %w[stack.converge stack.remove stack.run registry.prune].freeze
  belongs_to :app_record
  belongs_to :server
  enum :status, { pending: 0, claimed: 1, succeeded: 2, failed: 3 }
  validates :kind, inclusion: { in: KINDS }
  def terminal? = succeeded? || failed?
end
