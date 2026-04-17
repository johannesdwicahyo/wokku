class DatabaseService < ApplicationRecord
  belongs_to :server

  has_many :app_databases, dependent: :destroy
  has_many :backups, dependent: :destroy
  has_many :app_records, through: :app_databases

  enum :status, { running: 0, stopped: 1, creating: 2, error: 3 }

  validates :name, presence: true, uniqueness: { scope: :server_id }
  validates :service_type, presence: true, inclusion: {
    in: %w[postgres redis mysql mongodb memcached rabbitmq elasticsearch mariadb meilisearch clickhouse nats]
  }

  def service_tier
    @service_tier ||= ServiceTier.find_by(name: tier_name || "mini", service_type: service_type)
  end

  def backup_policy
    service_tier&.backup_policy || ServiceTier::BACKUP_POLICIES["mini"]
  end

  def auto_backup?
    backup_policy[:auto_backup]
  end

  def backup_limit_reached?
    cap = backup_policy[:free_cap]
    return false unless cap # paid tiers have no cap
    backups.completed.count >= cap
  end
end
