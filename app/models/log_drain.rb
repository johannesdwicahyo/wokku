class LogDrain < ApplicationRecord
  belongs_to :app_record
  validates :url, presence: true, format: { with: /\A(syslog|https?):\/\/.+\z/, message: "must be a valid syslog or HTTP URL" }
  validates :drain_type, inclusion: { in: %w[syslog https] }
end
