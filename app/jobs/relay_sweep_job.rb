# Hourly: emails the operator running apps whose env keys, app name or repo
# name look like a VPN/proxy relay (the 2026-11 free-tier relay cluster).
# Flag only — a human reads the code and decides (User#suspend_for_abuse!).
# Each app is reported once (relay_flagged_at).
# shortcut: names + env keys only; relays with innocent names and no tell-tale
# env (e.g. "loadku") need the host's docker-stats in≈out traffic signal.
class RelaySweepJob < ApplicationJob
  queue_as :default

  ENV_KEYS = %w[ARGO_AUTH ARGO_DOMAIN ARGO_PORT ARGO_TUNNEL CFIP CF_TUNNEL_TOKEN TUNNEL_TOKEN
                NEZHA_SERVER NEZHA_KEY SUB_PATH SERVERVPN_ORIGIN].freeze
  NAME_RE = /vmess|vless|xray|v2ray|trojan|nezha|shadowsocks|vpn/i

  def perform
    apps = AppRecord.where(status: :running, relay_flagged_at: nil).includes(team: :owner)
                    .reject { |a| a.team&.owner&.abuse_suspended? }
    keys = EnvVar.where(app_record_id: apps.map(&:id), key: ENV_KEYS).pluck(:app_record_id, :key)
                 .group_by(&:first).transform_values { |rows| rows.map(&:last) }

    hits = apps.filter_map do |app|
      repo = app.git_repo_full_name || app.github_repo_full_name || app.git_repository_url
      reasons = keys.fetch(app.id, []).map { |k| "env #{k}" }
      reasons << "name" if app.name.match?(NAME_RE)
      reasons << "repo #{repo}" if repo.to_s.match?(NAME_RE)
      [ app, reasons ] if reasons.any?
    end
    return if hits.empty?

    OpsMailer.relay_suspects(hits.map { |app, reasons| [ app.name, app.team&.owner&.email, reasons ] }).deliver_now
    AppRecord.where(id: hits.map { |app, _| app.id }).update_all(relay_flagged_at: Time.current)
  end
end
