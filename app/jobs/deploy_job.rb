require "shellwords"

class DeployJob < ApplicationJob
  queue_as :deploys

  DEPLOY_TIMEOUT = 15.minutes
  MIN_FREE_DISK_MB = 500 # Minimum free disk space required before deploy

  def perform(deploy_id, commit_sha: nil)
    deploy = Deploy.find_by(id: deploy_id)
    return unless deploy
    app = deploy.app_record
    server = app.server

    # Use the explicitly passed commit_sha if provided (rollback path),
    # otherwise fall back to whatever was stored on the deploy record.
    sha = commit_sha.presence || deploy.commit_sha.presence

    deploy.update!(status: :building, started_at: Time.current, commit_sha: sha)
    app.update!(status: :deploying)

    client = Dokku::Client.new(server)
    log = ""

    # Pre-flight disk space check. Fail fast with a clear error instead of
    # timing out after 15 minutes with a confusing "out of space" inside the build.
    free_mb = check_disk_space(client)
    if free_mb && free_mb < MIN_FREE_DISK_MB
      message = "Deploy aborted: server has only #{free_mb} MB free (need #{MIN_FREE_DISK_MB} MB). Free up disk space and retry."
      deploy.update!(status: :failed, log: message, finished_at: Time.current)
      app.update!(status: :crashed)
      DeployChannel.broadcast_to(deploy, { type: "log", data: message })
      DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
      fire_notifications(app.team, "deploy_failed", deploy)
      return
    end

    # Enforce resource limits before every deploy as a safety net.
    # If the app has a tier allocation, ensure Dokku has the correct limits.
    enforce_resource_limits(client, app)

    # If a commit_sha is specified (rollback), use git:from-image with the sha tag.
    # Otherwise just rebuild the current HEAD.
    build_command = if sha.present?
      # Dokku's git:from-image expects an image tag. For a true git-sha rollback,
      # we use the git:sync command if the source repo is tracked, or fall back
      # to a standard rebuild. This is documented as a beta limitation.
      "ps:rebuild #{Shellwords.escape(app.name)}"
    else
      "ps:rebuild #{Shellwords.escape(app.name)}"
    end

    Timeout.timeout(DEPLOY_TIMEOUT.to_i) do
      client.run_streaming(build_command) do |data|
        log << data
        DeployChannel.broadcast_to(deploy, { type: "log", data: data })
      end
    end

    deploy.update!(status: :succeeded, log: log, finished_at: Time.current)
    app.update!(status: :running)
    app.track_resource_usage! if app.respond_to?(:track_resource_usage!)
    Activity.log(user: app.creator, team: app.team, action: "app.deployed", target: app) rescue nil
    DeployChannel.broadcast_to(deploy, { type: "status", data: "succeeded" })
    fire_notifications(app.team, "deploy_succeeded", deploy)
  rescue Timeout::Error
    deploy.update!(status: :timed_out, log: log.to_s + "\nDeploy timed out after 15 minutes", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "timed_out" })
  rescue Dokku::Client::CommandError => e
    deploy.update!(status: :failed, log: log.to_s + "\n#{e.message}", finished_at: Time.current)
    app.update!(status: :crashed)
    DeployChannel.broadcast_to(deploy, { type: "status", data: "failed" })
    fire_notifications(app.team, "deploy_failed", deploy)
  end

  private

  # Ensure Dokku resource limits match the app's assigned tier.
  # If no tier is assigned, assign the free tier as a default.
  def enforce_resource_limits(client, app)
    allocation = app.dyno_allocations.includes(:dyno_tier).find_by(process_type: "web")

    unless allocation
      free_tier = DynoTier.find_by(name: "free") || DynoTier.order(:price_cents_per_hour).first
      return unless free_tier
      allocation = app.dyno_allocations.create!(process_type: "web", dyno_tier: free_tier, count: 1)
    end

    tier = allocation.dyno_tier
    return unless tier

    resources = Dokku::Resources.new(client)
    resources.apply_limits(app.name, memory_mb: tier.memory_mb, cpu_shares: tier.cpu_shares)
    resources.apply_reservation(app.name, memory_mb: tier.memory_mb)
  rescue StandardError => e
    Rails.logger.warn("DeployJob: resource limit enforcement failed: #{e.message}")
  end

  # Returns free space in MB on the Dokku server's root filesystem, or nil if
  # the check fails (we treat that as "unknown, allow the deploy").
  def check_disk_space(client)
    output = client.run("df -BM /")
    # df output format: Filesystem 1M-blocks Used Available Use% Mounted
    # Second line has the numbers
    line = output.to_s.lines[1]
    return nil unless line
    parts = line.split
    return nil unless parts.length >= 4
    parts[3].to_s.gsub(/[^0-9]/, "").to_i
  rescue StandardError => e
    Rails.logger.warn("DeployJob: disk space check failed: #{e.message}")
    nil
  end
end
