require "rails_helper"

RSpec.describe ObjectStorageMailer do
  it "mails the team owner and admins" do
    bucket = create(:object_storage_bucket, used_bytes: 9 * 1024**3)
    admin = create(:user)
    create(:team_membership, team: bucket.team, user: admin, role: :admin)
    mail = described_class.near_quota(bucket)
    expect(mail.to).to match_array([ bucket.team.owner.email, admin.email ])
    expect(mail.subject).to match(/storage/i)
    expect(mail.text_part.body.to_s).to include(bucket.name)
    expect(mail.html_part.body.to_s).to include(bucket.name)
  end
end
