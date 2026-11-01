class TeamMembership < ApplicationRecord
  belongs_to :user
  belongs_to :team

  enum :role, { viewer: 0, member: 1, admin: 2 }

  validates :user_id, uniqueness: { scope: :team_id }
  validates :role, presence: true

  class RoleError < StandardError; end

  # Shared by the dashboard and the API. A team always keeps at least one
  # admin, so the last admin can't demote themselves.
  def change_role!(new_role, by:)
    raise RoleError, "Invalid role. Use one of: #{self.class.roles.keys.join(', ')}." unless self.class.roles.key?(new_role)
    if user_id == by.id && new_role != "admin" && team.team_memberships.where(role: :admin).where.not(id: id).none?
      raise RoleError, "You're the last admin — promote someone else first."
    end

    update!(role: new_role)
  end
end
