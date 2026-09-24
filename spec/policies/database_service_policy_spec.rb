require "rails_helper"

RSpec.describe DatabaseServicePolicy do
  let(:team) { teams(:one) }
  let(:db) do
    create(:database_service, server: servers(:one), cpu: 0.25, memory_mb: 512, disk_gb: 10).tap do |d|
      d.app_databases.create!(app_record: app_records(:one), alias_name: "DATABASE")
    end
  end

  def member_with(role)
    create(:user).tap { |u| create(:team_membership, team: team, user: u, role: role) }
  end

  it "M1: a team viewer can't resize" do
    expect(described_class.new(member_with(:viewer), db).resize?).to be(false)
  end

  it "M1: a team member can resize" do
    expect(described_class.new(member_with(:member), db).resize?).to be(true)
  end
end
