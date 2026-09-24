class ResourceMailer < ApplicationMailer
  def disk_almost_full(user, label:, used_gb:, allocated_gb:)
    @label, @used_gb, @allocated_gb = label, used_gb, allocated_gb
    mail(to: user.email, subject: "#{label} is almost out of disk")
  end
end
