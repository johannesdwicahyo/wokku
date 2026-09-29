# The single catalog of API error codes. Every API failure renders through
# ApiErrors.payload so the three client surfaces (dashboard JS, CLI, MCP →
# Claude) see one shape: { error, error_code, hint, retryable }.
# hint is written FOR AN AGENT: state the next action, name the tool.
module ApiErrors
  CATALOG = {
    # auth / authz
    missing_token:     { status: :unauthorized, retryable: false,
                         message: "Missing authorization token",
                         hint: "Send Authorization: Bearer <token>. Create a token at wokku.cloud/dashboard/settings/tokens." },
    invalid_token:     { status: :unauthorized, retryable: false,
                         message: "Invalid or expired token",
                         hint: "The token was revoked or mistyped. Generate a new one at wokku.cloud/dashboard/settings/tokens." },
    not_authorized:    { status: :forbidden, retryable: false,
                         message: "Not authorized",
                         hint: "Your token's user is not a member of the team that owns this resource." },
    # resources
    not_found:         { status: :not_found, retryable: false,
                         message: "Resource not found",
                         hint: "Check the id/name; list the resource collection to see what exists." },
    validation_failed: { status: :unprocessable_entity, retryable: false,
                         message: "Validation failed",
                         hint: "Fix the fields in details and retry." },
    app_locked:        { status: :conflict, retryable: false,
                         message: "App is locked",
                         hint: "Unlock the app first (wokku_unlock_app), then retry." },
    already_exists:    { status: :conflict, retryable: false,
                         message: "Resource already exists",
                         hint: "Use the existing resource or pick a different name." },
    quota_exceeded:    { status: :unprocessable_entity, retryable: false,
                         message: "Plan quota exceeded",
                         hint: "Check wokku_get_usage / wokku_get_current_plan; upgrade the plan or free capacity." },
    account_suspended: { status: :payment_required, retryable: false,
                         message: "This account is suspended for an unpaid invoice",
                         hint: "Pay the overdue invoice at wokku.cloud/dashboard/invoices; apps can start/deploy again once it is paid." },
    invalid_time:      { status: :bad_request, retryable: false,
                         message: "Invalid time parameter",
                         hint: "Use ISO8601, e.g. 2026-07-04T12:00:00Z." },
    invalid_params:    { status: :bad_request, retryable: false,
                         message: "Invalid parameters",
                         hint: "Check the request body against the endpoint's schema." },
    # host / dokku
    host_unreachable:  { status: :service_unavailable, retryable: true,
                         message: "The host running this resource is unreachable",
                         hint: "Not your code. Check GET /api/v1/doctor for host heartbeat status; retry in ~1 minute." },
    host_down:         { status: :service_unavailable, retryable: true,
                         message: "The host running this resource is down",
                         hint: "Not your code — the platform host stopped heartbeating. The operator has been paged. Retry later." },
    deploy_lock_held:  { status: :conflict, retryable: true,
                         message: "A deploy is already in progress for this app",
                         hint: "Wait for the current deploy to finish; if it is stuck >15 min, StaleDeployLockJob clears it automatically, or run wokku doctor." },
    app_not_running:   { status: :conflict, retryable: false,
                         message: "The app has no running container",
                         hint: "The container exited. GET /apps/:id/logs (durable) and the recent CrashEvents show why; redeploy or wokku_restart_app." },
    plugin_missing:    { status: :not_implemented, retryable: false,
                         message: "Required Dokku plugin is not installed on this host",
                         hint: "Platform-side gap — report it; the operator must install the plugin on the host." },
    upload_not_configured: { status: :not_implemented, retryable: false,
                         message: "Tarball uploads are not configured on this server",
                         hint: "Platform-side gap — the operator must set WOKKU_BACKUP_S3_BUCKET/ENDPOINT/ACCESS_KEY_ID/SECRET_ACCESS_KEY." },
    archive_missing:   { status: :unprocessable_entity, retryable: false,
                         message: "The uploaded archive was not found in the store",
                         hint: "The archive_key doesn't point at an existing upload (expired, wrong key, or already consumed). Request a new upload slot (wokku_deploy_tarball / POST deploys/uploads) and re-upload." },
    not_found_on_host: { status: :not_found, retryable: false,
                         message: "Resource does not exist on the host",
                         hint: "Control-plane record and host state may have drifted; wokku doctor compares them." },
    rollback_artifact_missing: { status: :unprocessable_entity, retryable: false,
                         message: "No deployable artifact remains for this release",
                         hint: "Its rollback image/archive has been pruned or was never recorded. Trigger a fresh deploy instead of rolling back to this release." },
    domain_not_verified: { status: :forbidden, retryable: false,
                         message: "Domain is not verified for TLS issuance",
                         hint: "Add the domain to an app on this host and complete DNS verification (wokku_add_domain, then verify DNS) before HTTPS can be issued." },
    router_config_stale: { status: :conflict, retryable: true,
                         message: "Host router has not applied the latest routing config",
                         hint: "The host agent applies routing config within ~15s of a heartbeat. If this persists, check host status via GET /api/v1/doctor." },
    dokku_command_failed: { status: :bad_gateway, retryable: false,
                         message: "The host command failed",
                         hint: "Unclassified host error — the error message carries the raw output; if it persists, run wokku doctor." },
    passthrough_retired: { status: :gone, retryable: false,
                         message: "Raw dokku passthrough has been retired",
                         hint: "use the typed command for this operation — run `wokku help`" },
    storage_retired:     { status: :gone, retryable: false,
                         message: "Volume mount management has been retired",
                         hint: "Persistent volumes are platform-managed; contact support if your app needs a new mount." },
    buildpacks_retired:  { status: :gone, retryable: false,
                         message: "Buildpack configuration has been retired",
                         hint: "Builds are image-based (Dockerfile or nixpacks auto-detection); buildpack settings no longer apply." },
    # datastore ops (Track B Phase B4) — wokkud ServiceOp executor errors
    service_create_failed: { status: :bad_gateway, retryable: true,
                         message: "Datastore provisioning failed on the host.",
                         hint: "Check the op log (service_ops) for the engine error; retry the create after fixing the cause." },
    service_op_timeout:    { status: :service_unavailable, retryable: true,
                         message: "The host agent did not finish the datastore operation in time.",
                         hint: "The host may be slow or wokkud stopped mid-op. Verify host status, then retry." },
    tenant_exists:         { status: :conflict, retryable: false,
                         message: "A tenant with this slug already exists on the shared engine.",
                         hint: "Use the existing tenant or destroy it first." },
    quota_check_failed:    { status: :bad_gateway, retryable: true,
                         message: "The shared-engine quota sweep failed on the host.",
                         hint: "Transient host error — the next scheduled sweep retries automatically." },
    service_busy:          { status: :conflict, retryable: true,
                         message: "Another operation is already running for this datastore.",
                         hint: "Wait for the in-flight op to finish; ops on one service are serialized." },
    # Swarm lifecycle ops (Track B Phase B5a) — wokkud LifecycleOp executor errors
    formation_would_empty: { status: :unprocessable_entity, retryable: false,
                         message: "That formation change would leave the app with no running processes.",
                         hint: "Scale at least one process type up before scaling the others to zero." },
    image_pull_failed:     { status: :bad_gateway, retryable: true,
                         message: "The host could not pull the app's image.",
                         hint: "Check the op log (lifecycle_ops) for the registry error; retry the converge after fixing the cause." },
    converge_failed:       { status: :bad_gateway, retryable: true,
                         message: "Reconciling the app's Swarm formation failed on the host.",
                         hint: "Check the op log (lifecycle_ops) for the engine error; retry the converge after fixing the cause." },
    # Track B Phase B2: git-receive (wokkud_git)
    deploy_in_progress: { status: :conflict, retryable: true,
                         message: "A deploy is already in progress for this app",
                         hint: "Wait for the current deploy to finish or check `wokku deploys`." },
    ref_not_deployable: { status: :unprocessable_entity, retryable: false,
                         message: "Only main/master branches deploy",
                         hint: "Your ref was stored but not deployed. Push main or master to deploy." },
    archive_failed:     { status: :bad_gateway, retryable: true,
                         message: "Could not archive the pushed commit",
                         hint: "Retry the push; if it persists contact support." },
    app_not_on_server: { status: :not_found, retryable: false,
                         message: "That app is not on this server",
                         hint: "The agent asked about an app this server doesn't host — check server assignment." },
    internal_error:    { status: :internal_server_error, retryable: true,
                         message: "Internal error",
                         hint: "Unexpected failure on our side; it has been reported. Retry once; if it persists, wait a few minutes." }
  }.freeze

  def self.payload(code, message: nil, hint: nil, details: nil)
    entry = CATALOG.fetch(code)
    payload = {
      error: message || entry[:message],
      error_code: code.to_s,
      hint: hint || entry[:hint],
      retryable: entry[:retryable]
    }
    if details
      payload[:details] = details
      payload[:errors]  = details # legacy shape kept for old clients
    end
    payload
  end

  def self.status(code) = CATALOG.fetch(code)[:status]

  # Maps the ad-hoc `code:` symbols raised by app/services/apps/*/error.rb
  # subclasses (Apps::Lifecycle::Error, Apps::Settings::Error,
  # Apps::DevSession::Error, Apps::Cron::Error) onto the catalog above, so
  # every service-error rescue site renders through the same typed shape.
  SERVICE_CODE_MAP = {
    dokku_error:         :dokku_command_failed,
    container_not_found: :app_not_running,
    name_taken:          :already_exists,
    invalid_name:        :invalid_params,
    invalid_email:       :invalid_params,
    invalid:             :invalid_params,
    no_ssh_key:          :validation_failed,
    no_postgres:         :validation_failed,
    transfer_pending:    :already_exists
  }.freeze

  def self.from_service_code(code) = SERVICE_CODE_MAP.fetch(code, :invalid_params)
end
