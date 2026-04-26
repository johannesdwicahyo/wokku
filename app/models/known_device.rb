class KnownDevice < ApplicationRecord
  belongs_to :user

  validates :ip, :user_agent_hash, :first_seen_at, :last_seen_at, presence: true

  # Called from the sign-in path. Records the user's (ip, user_agent) as a
  # known device; if we haven't seen it before, fires an alert email + team
  # activity log entry. Returns the device. Swallows errors — must never
  # block a successful sign-in.
  def self.track!(user:, ip:, user_agent:)
    ip = ip.to_s.presence || "unknown"
    ua_hash = fingerprint(user_agent)
    now = Time.current

    device = user.known_devices.find_or_initialize_by(ip: ip, user_agent_hash: ua_hash)
    if device.new_record?
      device.assign_attributes(
        user_agent_label: summarise(user_agent),
        first_seen_at: now,
        last_seen_at: now
      )
      device.save!
      SecurityMailer.new_device_sign_in(user, device).deliver_later
      team = user.teams.first
      if team
        Activity.log(
          user: user, team: team,
          action: "session.new_device",
          metadata: { ip: ip, device: device.user_agent_label, channel: "app" }
        )
      end
    else
      device.update_column(:last_seen_at, now)
    end
    device
  rescue StandardError => e
    Rails.logger.warn("KnownDevice.track! failed for user #{user.id}: #{e.class}: #{e.message}")
    nil
  end

  # Compute a stable fingerprint of the user-agent string. We store only the
  # hash — not the UA itself — so a DB leak can't be used to fingerprint a
  # user's devices. `user_agent_label` keeps a coarse, human-readable summary
  # ("Chrome on macOS") for the alert email; it doesn't have to be exact.
  def self.fingerprint(user_agent)
    Digest::SHA256.hexdigest(user_agent.to_s)
  end

  def self.summarise(user_agent)
    return "unknown browser" if user_agent.blank?
    ua = user_agent.to_s
    browser =
      case ua
      when /Firefox\//i    then "Firefox"
      when /Edg\//i        then "Edge"
      when /OPR\/|Opera/i  then "Opera"
      when /Chrome\//i     then "Chrome"
      when /Safari\//i     then "Safari"
      else "a browser"
      end
    os =
      case ua
      when /iPhone|iPad|iPod/i then "iOS"
      when /Android/i          then "Android"
      when /Mac OS X/i         then "macOS"
      when /Windows/i          then "Windows"
      when /Linux/i            then "Linux"
      else "an unknown device"
      end
    "#{browser} on #{os}"
  end
end
