class Activity < ApplicationRecord
  belongs_to :user
  belongs_to :team

  validates :action, presence: true

  scope :recent, -> { order(created_at: :desc).limit(50) }
  scope :for_team, ->(team) { where(team: team) }

  # Predefined actions
  ACTIONS = {
    "app.created" => "created app",
    "app.destroyed" => "destroyed app",
    "app.deployed" => "deployed",
    "app.restarted" => "restarted app",
    "app.stopped" => "stopped app",
    "app.started" => "started app",
    "config.updated" => "updated config for",
    "domain.added" => "added domain to",
    "domain.removed" => "removed domain from",
    "database.created" => "created database",
    "database.destroyed" => "destroyed database",
    "database.linked" => "linked database to",
    "server.created" => "added server",
    "server.destroyed" => "removed server",
    "backup.created" => "backed up",
    "backup.restored" => "restored",
    "github.connected" => "connected GitHub repo to",
    "github.disconnected" => "disconnected GitHub from",
    "template.deployed" => "deployed template",
    "notification.created" => "created notification rule",
    "team.member_added" => "added team member",
    "team.member_removed" => "removed team member"
  }.freeze

  def description
    ACTIONS[action] || action
  end

  def self.log(user:, team:, action:, target: nil, metadata: {})
    create!(
      user: user,
      team: team,
      action: action,
      target_type: target&.class&.name,
      target_id: target&.id,
      target_name: target.try(:name) || target.try(:hostname) || metadata[:name],
      metadata: metadata
    )
  rescue => e
    Rails.logger.warn("Activity.log failed: #{e.message}")
  end
end
