class ObjectStorageMailer < ApplicationMailer
  def near_quota(bucket)
    @bucket = bucket
    team = bucket.team
    to = ([ team.owner ] + team.users.merge(TeamMembership.admin)).uniq.map(&:email)
    mail(to: to, subject: "Your object storage is almost full (#{bucket.name})")
  end
end
