require "net/http"

# Weekly smoke test of the framework starters: deploy each starter template
# to a throwaway app through the normal TemplateDeployer path, expect its URL
# to answer 2xx/3xx, delete it, then email ADMIN_EMAIL any failures. Catches
# runtime rot (an end-of-life Node, a toolchain that no longer downloads)
# before a customer's first deploy does.
#
# One starter at a time, and every wait is a re-enqueue rather than a sleep:
# a build takes minutes and must not hold a Puma-hosted worker thread, and a
# single throwaway app stays inside the operator team's sleeping-box cap.
class StarterCheckJob < ApplicationJob
  queue_as :default

  POLL = 30.seconds
  BUILD_TIMEOUT = 20.minutes
  PROBE_TRIES = 4
  STARTER_REPO = %r{github\.com/johannesdwicahyo/wokku-.+-starter}

  def self.starter_slugs
    TemplateRegistry.new.all.select { |t| t[:repo].to_s.match?(STARTER_REPO) }.map { |t| t[:slug] }.sort
  end

  def self.app_name(slug) = "zz-starter-#{slug}"

  # remaining: slugs still to check (head = current); results: slug => "ok" or a reason.
  def perform(remaining = self.class.starter_slugs, results = {}, app_id = nil, since = nil, probes = 0)
    return finish(results) if remaining.empty?

    if app_id
      check(remaining, results, app_id, since, probes)
    else
      start(remaining, results)
    end
  end

  private

  def start(remaining, results)
    slug = remaining.first
    template = TemplateRegistry.new.find(slug)
    user = User.admin.order(:created_at).first
    server = Server.all.find(&:wokkud_services_enabled?)
    return record(remaining, results, nil, "no admin user or wokkud server") unless template && user && server

    # A run that died mid-check leaves its app behind; clear it first.
    if (stale = AppRecord.find_by(name: self.class.app_name(slug)))
      AppDestroyJob.perform_later(stale.id)
      return self.class.set(wait: 1.minute).perform_later(remaining, results)
    end

    result = TemplateDeployer.new(template: template, app_name: self.class.app_name(slug), server: server, user: user).deploy!
    app = AppRecord.find_by(name: self.class.app_name(slug))
    if result[:async] && app
      self.class.set(wait: POLL).perform_later(remaining, results, app.id, Time.current.iso8601, 0)
    else
      record(remaining, results, app, "deploy refused: #{result[:error]}")
    end
  rescue StandardError => e
    record(remaining, results, AppRecord.find_by(name: self.class.app_name(slug)), "#{e.class}: #{e.message}")
  end

  def check(remaining, results, app_id, since, probes)
    app = AppRecord.find_by(id: app_id)
    return record(remaining, results, nil, "app vanished mid-check") unless app

    deploy = app.deploys.order(:created_at).last
    if deploy&.succeeded?
      code = probe(app)
      return record(remaining, results, app, "ok") if code&.between?(200, 399)
      return record(remaining, results, app, "deployed but URL answered #{code || 'nothing'}") if probes + 1 >= PROBE_TRIES

      self.class.set(wait: POLL).perform_later(remaining, results, app_id, since, probes + 1)
    elsif deploy&.failed? || deploy&.timed_out?
      record(remaining, results, app, "build #{deploy.status}: #{deploy.log.to_s.lines.last(3).join.strip.truncate(300)}")
    elsif Time.zone.parse(since) < BUILD_TIMEOUT.ago
      record(remaining, results, app, "no finished deploy after #{BUILD_TIMEOUT.inspect}")
    else
      self.class.set(wait: POLL).perform_later(remaining, results, app_id, since, probes)
    end
  end

  def probe(app)
    host = app.domains.order(:created_at).first&.hostname or return nil
    uri = URI("https://#{host}/")
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |h| h.get("/") }
    # Caddy answers a host it has no route for with an empty 200 — that is not
    # the app (it made the rails starter "pass" with no root page, 2026-11-21).
    res.code == "200" && res.body.to_s.empty? ? nil : res.code.to_i
  rescue StandardError
    nil
  end

  # Records the current starter's outcome, deletes its app, moves to the next
  # one after the delete has had time to free the box.
  def record(remaining, results, app, outcome)
    AppDestroyJob.perform_later(app.id) if app
    self.class.set(wait: 1.minute).perform_later(remaining.drop(1), results.merge(remaining.first => outcome))
  end

  def finish(results)
    failures = results.reject { |_, outcome| outcome == "ok" }
    Rails.logger.info("StarterCheckJob: #{results.size - failures.size}/#{results.size} starters ok")
    OpsMailer.starter_check_failed(failures, results.size).deliver_later if failures.any?
  end
end
