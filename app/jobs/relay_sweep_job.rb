# Hourly: emails the operator running (or sleeping — they wake on a request)
# apps whose env keys, app name or repo name look like a VPN/proxy relay (the
# 2026-11 free-tier relay cluster). Each app is reported once (relay_flagged_at).
#
# Flag only — a human reads the code and decides (User#suspend_for_abuse!) —
# EXCEPT ban evasion: an app whose repo owner belongs to an already-suspended
# user AND that shows a relay signal gets its owner suspended automatically
# (2026-11-22: one person, three accounts). A banned owner with no relay
# signal is only flagged, so deploying someone's legit public repo can't get
# an innocent account suspended.
# shortcut: names + env keys only; relays with innocent names and no tell-tale
# env (e.g. "loadku") need the host's docker-stats in≈out traffic signal.
class RelaySweepJob < ApplicationJob
  queue_as :default

  ENV_KEYS = %w[ARGO_AUTH ARGO_DOMAIN ARGO_PORT ARGO_TUNNEL CFIP CF_TUNNEL_TOKEN TUNNEL_TOKEN
                NEZHA_SERVER NEZHA_KEY SUB_PATH SERVERVPN_ORIGIN].freeze
  NAME_RE = /vmess|vless|xray|v2ray|trojan|nezha|shadowsocks|vpn/i

  def perform
    apps = AppRecord.where(status: %i[running sleeping], relay_flagged_at: nil).includes(team: :owner)
                    .reject { |a| a.team&.owner&.abuse_suspended? }
    keys = EnvVar.where(app_record_id: apps.map(&:id), key: ENV_KEYS).pluck(:app_record_id, :key)
                 .group_by(&:first).transform_values { |rows| rows.map(&:last) }

    hits = apps.filter_map do |app|
      reasons = self.class.verdict(app, self.class.reasons_for(app, keys.fetch(app.id, [])))
      [ app, reasons ] if reasons.any?
    end
    return if hits.empty?

    OpsMailer.relay_suspects(hits.map { |app, reasons| [ app.name, app.team&.owner&.email, reasons ] }).deliver_now
    AppRecord.where(id: hits.map { |app, _| app.id }).update_all(relay_flagged_at: Time.current)
  end

  # Why an app looks like a relay ([] = it doesn't). env_keys defaults to a
  # lookup for callers outside the batched sweep (the deploy gate).
  def self.reasons_for(app, env_keys = EnvVar.where(app_record_id: app.id, key: ENV_KEYS).pluck(:key))
    repo = app.git_repo_full_name || app.github_repo_full_name || app.git_repository_url
    reasons = env_keys.map { |k| "env #{k}" }
    reasons << "name" if app.name.match?(NAME_RE)
    reasons << "repo #{repo}" if repo.to_s.match?(NAME_RE)
    reasons
  end

  # Applies the ban-evasion rule: banned repo owner + any relay reason =
  # suspend the owner now; banned owner alone = just say so. Returns the
  # reasons to report ([] = nothing to report).
  def self.verdict(app, reasons)
    return reasons unless User.banned_repo_owner?(app.repo_owner)
    return reasons + [ "banned repo owner #{app.repo_owner}" ] if reasons.empty?

    app.team.owner.suspend_for_abuse!
    [ "AUTO-SUSPENDED: ban evasion, repo owner #{app.repo_owner}" ] + reasons
  end
end
