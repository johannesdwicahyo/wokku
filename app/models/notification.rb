class Notification < ApplicationRecord
  belongs_to :team
  belongs_to :app_record, optional: true

  enum :channel, { email: 0, slack: 1, webhook: 2, discord: 3, telegram: 4, push: 5 }

  validates :channel, presence: true
  validates :events, presence: true

  DEFAULT_PUSH_EVENTS = %w[app_down app_recovered app_crashed deploy_failed backup_failed].freeze

  # First phone registered -> on-call push for each of the user's teams that
  # has no push rule yet. Teams that configured (or deleted) their own keep it.
  def self.ensure_default_push_for!(user)
    user.teams.where.not(id: where(channel: :push).select(:team_id)).find_each do |team|
      team.notifications.create!(channel: :push, events: DEFAULT_PUSH_EVENTS)
    end
  end
end
