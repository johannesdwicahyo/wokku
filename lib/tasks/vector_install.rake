require "shellwords"
require "base64"

# Install + configure Vector on a Dokku host so it ships container logs
# to wokku-cloud's POST /api/v1/logs/ingest endpoint. Runs end-to-end
# remotely via root SSH (same key wokku already uses for MetricsPollJob
# and ProvisionServerJob).
#
#   bin/rails 'vector:install[jkt-01]'                       # by server.name
#   bin/rails 'vector:install[43.159.57.11]'                 # by server.host
#   bin/rails 'vector:install[jkt-01,https://wokku.cloud]'   # override ingest URL
#
# Idempotent: re-running rewrites the config + restarts vector. Safe to
# run after the wokku.cloud URL or token rotates.
#
# Security note: all file contents are base64-encoded before being sent
# over SSH and decoded on the host. No shell interpolation of the YAML
# or token. Inputs (server_ref, ingest_url) are validated before use.
namespace :vector do
  INGEST_URL_PATTERN = %r{\Ahttps?://[a-z0-9.\-]+(:\d+)?(/[a-z0-9/_.\-]*)?\z}i.freeze

  desc "Install + configure Vector on a Dokku host (apt + config + systemd)"
  task :install, %i[server_ref ingest_url requests_url] => :environment do |_, args|
    server_ref = args[:server_ref].to_s
    ingest_url   = args[:ingest_url].presence   || ENV.fetch("WOKKU_INGEST_URL",   "https://wokku.cloud/api/v1/logs/ingest")
    requests_url = args[:requests_url].presence || ENV.fetch("WOKKU_REQUESTS_INGEST_URL", default_requests_url(ingest_url))

    abort "Usage: bin/rails 'vector:install[server_name_or_host]'" if server_ref.empty?
    abort "Invalid ingest_url: #{ingest_url.inspect}"     unless ingest_url.match?(INGEST_URL_PATTERN)
    abort "Invalid requests_url: #{requests_url.inspect}" unless requests_url.match?(INGEST_URL_PATTERN)

    server = Server.find_by(name: server_ref) || Server.find_by(host: server_ref) ||
             Server.find_by(id: server_ref)
    abort "Server not found: #{server_ref.inspect}" unless server
    abort "Server has no ssh_private_key — can't SSH" if server.ssh_private_key.blank?

    server.ensure_ingest_token
    server.save! if server.changed?
    token = server.ingest_token
    abort "Server token format unexpected" unless token.match?(/\A[a-f0-9]{32,}\z/)

    config_yaml = vector_config_yaml(ingest_url, requests_url)
    env_file_content = "WOKKU_INGEST_TOKEN=#{token}\n"
    systemd_drop_in = "[Service]\nEnvironmentFile=/etc/vector/wokku.env\n"

    puts "vector:install → #{server.name} (#{server.host})"
    puts "  ingest URL: #{ingest_url}"
    puts "  token: …#{token.last(8)}"
    puts

    ssh_options = { port: server.port || 22, non_interactive: true, timeout: 20,
                    key_data: Array(server.ssh_private_key).reject(&:blank?) }

    Net::SSH.start(server.host, "root", **ssh_options) do |ssh|
      step ssh, "Adding Vector apt repository (timber.io)",
        "curl -1sLf https://repositories.timber.io/public/vector/cfg/setup/bash.deb.sh | bash"

      step ssh, "apt-get install vector",
        "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vector"

      step ssh, "mkdir -p /etc/vector + write config", install_file(
        path: "/etc/vector/vector.yaml", content: config_yaml, mode: "0644"
      )

      step ssh, "Write /etc/vector/wokku.env (chmod 600)", install_file(
        path: "/etc/vector/wokku.env", content: env_file_content, mode: "0600"
      )

      step ssh, "Write systemd EnvironmentFile drop-in", install_file(
        path: "/etc/systemd/system/vector.service.d/wokku.conf", content: systemd_drop_in, mode: "0644"
      )

      step ssh, "systemctl daemon-reload + enable + restart",
        "systemctl daemon-reload && systemctl enable --now vector && systemctl restart vector"

      sleep 3

      tail = ssh.exec!("journalctl -u vector -n 30 --no-pager --output=cat 2>&1").to_s
      if tail.match?(/error|failed/i) && !tail.match?(/0 errors/)
        puts "  ⚠ Vector started but log tail has error-ish lines — review:"
        puts tail.lines.last(15).map { |l| "    | #{l}" }.join
      else
        puts "  ✓ Vector running cleanly"
      end
    end

    puts
    puts "Done. Verify with:"
    puts "  bundle exec kamal app exec --reuse --quiet \\"
    puts "    \"bin/rails runner 'puts Log.where(server_id: %q{#{server.id}}).order(ts: :desc).limit(5).pluck(:ts, :container, :line)'\""
  end

  desc "Print the Vector config that vector:install would write (for review)"
  task :show_config, %i[ingest_url requests_url] => :environment do |_, args|
    ingest_url = args[:ingest_url].presence || "https://wokku.cloud/api/v1/logs/ingest"
    requests_url = args[:requests_url].presence || default_requests_url(ingest_url)
    puts vector_config_yaml(ingest_url, requests_url)
  end

  # Derive the requests ingest URL from the logs one when not given explicitly:
  # /api/v1/logs/ingest → /api/v1/requests/ingest. Keeps the common case
  # (default wokku.cloud) frictionless while still allowing override.
  def default_requests_url(logs_url)
    logs_url.sub(%r{/api/v1/logs/ingest\z}, "/api/v1/requests/ingest")
  end

  # Build a remote command that decodes file content from base64 and
  # writes it atomically with the requested mode. No shell interpolation
  # of the content itself.
  def install_file(path:, content:, mode:)
    dir = File.dirname(path)
    b64 = Base64.strict_encode64(content)
    "mkdir -p #{Shellwords.escape(dir)} && " \
    "umask 077 && " \
    "echo #{Shellwords.escape(b64)} | base64 -d > #{Shellwords.escape(path)}.tmp && " \
    "chmod #{Shellwords.escape(mode)} #{Shellwords.escape(path)}.tmp && " \
    "mv #{Shellwords.escape(path)}.tmp #{Shellwords.escape(path)}"
  end

  def step(ssh, label, command)
    print "  → #{label}... "
    out = ""
    err = ""
    exit_code = 0
    ssh.open_channel do |ch|
      ch.exec(command) do |_ch, success|
        raise "Failed to exec: #{label}" unless success
        ch.on_data { |_, data| out << data }
        ch.on_extended_data { |_, _, data| err << data }
        ch.on_request("exit-status") { |_, data| exit_code = data.read_long }
      end
    end.wait

    if exit_code.zero?
      puts "ok"
    else
      puts "FAILED (exit #{exit_code})"
      puts "    stdout: #{out.lines.last(5).join}"
      puts "    stderr: #{err.lines.last(5).join}"
      abort "Aborting — fix the error above and retry."
    end
  end

  def vector_config_yaml(ingest_url, requests_url)
    <<~YAML
      sources:
        docker:
          type: docker_logs
          # Tail all containers on the host. wokku's ingest controllers
          # filter on their side; nginx-proxy lines are also routed
          # through a separate parse pipeline below.

      transforms:
        to_wokku_schema:
          type: remap
          inputs: [docker]
          source: |
            .ts = .timestamp
            .container = .container_name
            .message = .message
            .level = ""
            del(.timestamp)
            del(.container_name)
            del(.container_id)
            del(.image)
            del(.host)
            del(.source_type)
            del(.stream)
            del(.label)

        # nginx-proxy access-log parser. Dokku's vhost log_format:
        #   $host $remote_addr - $remote_user [$time_local]
        #   "$request" $status $body_bytes_sent "$http_referer"
        #   "$http_user_agent" [$request_time]
        # request_time is appended when nginx is built with it (Dokku
        # ships this in vhost.conf by default since 0.27+). It's
        # optional in the regex below.
        parse_nginx_requests:
          type: remap
          inputs: [docker]
          source: |
            # Only nginx-proxy container lines. Drop everything else.
            if .container_name != "nginx-proxy" {
              abort
            }
            parsed, err = parse_regex(.message, r'^(?P<host>\\S+) (?P<remote_addr>\\S+) - \\S+ \\[[^\\]]+\\] "(?P<method>\\S+) (?P<path>\\S+) HTTP/\\S+" (?P<status>\\d+) (?P<bytes_sent>\\S+)(?: "[^"]*" "[^"]*"(?: (?P<request_time>\\d+\\.\\d+))?)?')
            if err != null {
              abort
            }
            .ts = .timestamp
            .host = parsed.host
            .method = parsed.method
            .path = parsed.path
            .status = to_int!(parsed.status)
            bytes, _ = to_int(parsed.bytes_sent)
            .bytes_sent = bytes
            if parsed.request_time != null {
              rt_sec, _ = to_float(parsed.request_time)
              .response_time_ms = to_int(rt_sec * 1000.0) ?? null
            }
            .remote_addr = parsed.remote_addr
            # Server-side ingest controller resolves app via host → Domain
            # → AppRecord, but we also hint at it via `container` so the
            # existing container.split(".").first lookup falls through
            # cleanly when this row is rendered.
            .container = parsed.host
            del(.timestamp)
            del(.container_name)
            del(.container_id)
            del(.image)
            del(.source_type)
            del(.stream)
            del(.label)
            del(.message)

      sinks:
        wokku:
          type: http
          inputs: [to_wokku_schema]
          uri: #{ingest_url}
          method: post
          encoding:
            codec: json
          framing:
            method: newline_delimited
          request:
            headers:
              Authorization: "Bearer ${WOKKU_INGEST_TOKEN}"
              Content-Type: application/x-ndjson
          batch:
            max_events: 500
            timeout_secs: 5
          buffer:
            type: disk
            max_size: 268435456
            when_full: drop_newest

        wokku_requests:
          type: http
          inputs: [parse_nginx_requests]
          uri: #{requests_url}
          method: post
          encoding:
            codec: json
          framing:
            method: newline_delimited
          request:
            headers:
              Authorization: "Bearer ${WOKKU_INGEST_TOKEN}"
              Content-Type: application/x-ndjson
          batch:
            max_events: 500
            timeout_secs: 5
          buffer:
            type: disk
            max_size: 268435456
            when_full: drop_newest
    YAML
  end
end
