class DatabaseService < ApplicationRecord
  belongs_to :server

  has_many :app_databases, dependent: :destroy
  has_many :app_records, through: :app_databases

  enum :status, { running: 0, stopped: 1, creating: 2, error: 3 }

  validates :name, presence: true, uniqueness: { scope: :server_id }
  validates :service_type, presence: true, inclusion: {
    in: %w[postgres redis mysql mongodb memcached rabbitmq elasticsearch mariadb minio]
  }
end
