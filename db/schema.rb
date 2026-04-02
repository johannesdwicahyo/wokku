# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_02_085232) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "activities", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.bigint "target_id"
    t.string "target_name"
    t.string "target_type"
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.index ["target_type", "target_id"], name: "index_activities_on_target_type_and_target_id"
    t.index ["team_id", "created_at"], name: "index_activities_on_team_id_and_created_at"
    t.index ["team_id"], name: "index_activities_on_team_id"
    t.index ["user_id"], name: "index_activities_on_user_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name"
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "app_databases", force: :cascade do |t|
    t.string "alias_name"
    t.bigint "app_record_id", null: false
    t.datetime "created_at", null: false
    t.bigint "database_service_id", null: false
    t.datetime "updated_at", null: false
    t.index ["app_record_id", "database_service_id"], name: "index_app_databases_on_app_record_id_and_database_service_id", unique: true
    t.index ["app_record_id"], name: "index_app_databases_on_app_record_id"
    t.index ["database_service_id"], name: "index_app_databases_on_database_service_id"
  end

  create_table "app_records", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.string "deploy_branch", default: "main"
    t.string "git_repository_url"
    t.string "github_repo_full_name"
    t.string "github_webhook_secret"
    t.string "name", null: false
    t.bigint "server_id", null: false
    t.integer "status", default: 0
    t.datetime "synced_at"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_app_records_on_created_by_id"
    t.index ["github_repo_full_name"], name: "index_app_records_on_github_repo_full_name"
    t.index ["name", "server_id"], name: "index_app_records_on_name_and_server_id", unique: true
    t.index ["server_id"], name: "index_app_records_on_server_id"
    t.index ["team_id"], name: "index_app_records_on_team_id"
  end

  create_table "backup_destinations", force: :cascade do |t|
    t.string "access_key_id"
    t.string "bucket", null: false
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true
    t.string "endpoint_url"
    t.string "path_prefix", default: "wokku-backups"
    t.string "provider", default: "s3"
    t.string "region", default: "us-east-1"
    t.integer "retention_days", default: 30
    t.string "secret_access_key"
    t.bigint "server_id", null: false
    t.datetime "updated_at", null: false
    t.index ["server_id"], name: "index_backup_destinations_on_server_id", unique: true
  end

  create_table "backups", force: :cascade do |t|
    t.bigint "backup_destination_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "database_service_id", null: false
    t.text "error_message"
    t.string "s3_key", null: false
    t.bigint "size_bytes"
    t.datetime "started_at"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["backup_destination_id"], name: "index_backups_on_backup_destination_id"
    t.index ["database_service_id", "created_at"], name: "index_backups_on_database_service_id_and_created_at"
    t.index ["database_service_id"], name: "index_backups_on_database_service_id"
  end

  create_table "certificates", force: :cascade do |t|
    t.boolean "auto_renew", default: true
    t.datetime "created_at", null: false
    t.bigint "domain_id", null: false
    t.datetime "expires_at"
    t.datetime "updated_at", null: false
    t.index ["domain_id"], name: "index_certificates_on_domain_id"
  end

  create_table "cloud_credentials", force: :cascade do |t|
    t.string "api_key"
    t.datetime "created_at", null: false
    t.string "name"
    t.string "provider", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "provider"], name: "index_cloud_credentials_on_team_id_and_provider"
    t.index ["team_id"], name: "index_cloud_credentials_on_team_id"
  end

  create_table "database_services", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "server_id", null: false
    t.string "service_type"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["server_id", "name"], name: "index_database_services_on_server_id_and_name", unique: true
    t.index ["server_id"], name: "index_database_services_on_server_id"
  end

  create_table "deploys", force: :cascade do |t|
    t.bigint "app_record_id", null: false
    t.string "commit_sha"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.text "log"
    t.bigint "release_id"
    t.datetime "started_at"
    t.integer "status", default: 0
    t.datetime "updated_at", null: false
    t.index ["app_record_id"], name: "index_deploys_on_app_record_id"
    t.index ["release_id"], name: "index_deploys_on_release_id"
  end

  create_table "device_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "platform", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["token"], name: "index_device_tokens_on_token", unique: true
    t.index ["user_id"], name: "index_device_tokens_on_user_id"
  end

  create_table "domains", force: :cascade do |t|
    t.bigint "app_record_id", null: false
    t.datetime "created_at", null: false
    t.boolean "dns_verified", default: false
    t.string "hostname"
    t.boolean "ssl_enabled", default: false
    t.datetime "updated_at", null: false
    t.index ["app_record_id"], name: "index_domains_on_app_record_id"
    t.index ["hostname"], name: "index_domains_on_hostname", unique: true
  end

  create_table "dyno_allocations", force: :cascade do |t|
    t.bigint "app_record_id", null: false
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.bigint "dyno_tier_id", null: false
    t.string "process_type", null: false
    t.datetime "updated_at", null: false
    t.index ["app_record_id", "process_type"], name: "index_dyno_allocations_on_app_record_id_and_process_type", unique: true
    t.index ["app_record_id"], name: "index_dyno_allocations_on_app_record_id"
    t.index ["dyno_tier_id"], name: "index_dyno_allocations_on_dyno_tier_id"
  end

  create_table "dyno_tiers", force: :cascade do |t|
    t.decimal "cpu_shares", precision: 4, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.integer "max_per_user"
    t.integer "memory_mb", null: false
    t.string "name", null: false
    t.decimal "price_cents_per_hour", precision: 10, scale: 4, default: "0.0", null: false
    t.integer "price_cents_per_month"
    t.boolean "scalable", default: false, null: false
    t.boolean "sleeps", default: false, null: false
    t.integer "storage_mb", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_dyno_tiers_on_name", unique: true
  end

  create_table "env_vars", force: :cascade do |t|
    t.bigint "app_record_id", null: false
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["app_record_id", "key"], name: "index_env_vars_on_app_record_id_and_key", unique: true
    t.index ["app_record_id"], name: "index_env_vars_on_app_record_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.integer "amount_cents"
    t.integer "amount_idr", default: 0
    t.datetime "created_at", null: false
    t.datetime "due_date"
    t.string "ipaymu_payment_url"
    t.string "ipaymu_transaction_id"
    t.datetime "paid_at"
    t.string "payment_method"
    t.string "period_label"
    t.string "reference_id"
    t.integer "status", default: 0
    t.string "stripe_invoice_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["reference_id"], name: "index_invoices_on_reference_id", unique: true
    t.index ["user_id"], name: "index_invoices_on_user_id"
  end

  create_table "metrics", force: :cascade do |t|
    t.bigint "app_record_id", null: false
    t.float "cpu_percent"
    t.datetime "created_at", null: false
    t.bigint "memory_limit"
    t.bigint "memory_usage"
    t.datetime "recorded_at"
    t.datetime "updated_at", null: false
    t.index ["app_record_id", "recorded_at"], name: "index_metrics_on_app_record_id_and_recorded_at"
    t.index ["app_record_id"], name: "index_metrics_on_app_record_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "app_record_id"
    t.integer "channel"
    t.json "config"
    t.datetime "created_at", null: false
    t.json "events"
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["app_record_id"], name: "index_notifications_on_app_record_id"
    t.index ["team_id"], name: "index_notifications_on_team_id"
  end

  create_table "oss_revenue_shares", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "funding_url"
    t.integer "paid_cents", default: 0
    t.string "template_slug", null: false
    t.integer "total_cents", default: 0
    t.datetime "updated_at", null: false
    t.index ["template_slug"], name: "index_oss_revenue_shares_on_template_slug", unique: true
  end

  create_table "plans", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "max_apps", null: false
    t.integer "max_databases"
    t.integer "max_dynos"
    t.string "name", null: false
    t.integer "price_cents_per_month"
    t.string "stripe_price_id"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_plans_on_name", unique: true
    t.index ["stripe_price_id"], name: "index_plans_on_stripe_price_id", unique: true
  end

  create_table "process_scales", force: :cascade do |t|
    t.bigint "app_record_id", null: false
    t.integer "count", default: 1
    t.datetime "created_at", null: false
    t.string "process_type"
    t.datetime "updated_at", null: false
    t.index ["app_record_id", "process_type"], name: "index_process_scales_on_app_record_id_and_process_type", unique: true
    t.index ["app_record_id"], name: "index_process_scales_on_app_record_id"
  end

  create_table "releases", force: :cascade do |t|
    t.bigint "app_record_id", null: false
    t.datetime "created_at", null: false
    t.bigint "deploy_id"
    t.string "description"
    t.datetime "updated_at", null: false
    t.integer "version"
    t.index ["app_record_id", "version"], name: "index_releases_on_app_record_id_and_version", unique: true
    t.index ["app_record_id"], name: "index_releases_on_app_record_id"
    t.index ["deploy_id"], name: "index_releases_on_deploy_id"
  end

  create_table "resource_usages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}
    t.decimal "price_cents_per_hour", precision: 10, scale: 4, default: "0.0", null: false
    t.string "resource_id_ref", null: false
    t.string "resource_type", null: false
    t.datetime "started_at", null: false
    t.datetime "stopped_at"
    t.string "tier_name", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["resource_type", "resource_id_ref"], name: "index_resource_usages_on_resource_type_and_resource_id_ref"
    t.index ["user_id", "stopped_at"], name: "index_resource_usages_on_user_id_and_stopped_at"
    t.index ["user_id"], name: "index_resource_usages_on_user_id"
  end

  create_table "servers", force: :cascade do |t|
    t.integer "capacity_total_mb", default: 0
    t.integer "capacity_used_mb", default: 0
    t.string "cloud_provider"
    t.string "cloud_server_id"
    t.datetime "created_at", null: false
    t.string "host", null: false
    t.integer "monthly_cost_cents"
    t.string "name", null: false
    t.integer "port", default: 22
    t.string "region"
    t.text "ssh_private_key"
    t.string "ssh_user", default: "dokku"
    t.integer "status", default: 0
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["name", "team_id"], name: "index_servers_on_name_and_team_id", unique: true
    t.index ["team_id"], name: "index_servers_on_team_id"
  end

  create_table "service_tiers", force: :cascade do |t|
    t.boolean "available", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.decimal "price_cents_per_hour", precision: 10, scale: 4, default: "0.0", null: false
    t.string "service_type", null: false
    t.jsonb "spec", default: {}
    t.datetime "updated_at", null: false
    t.index ["service_type", "name"], name: "index_service_tiers_on_service_type_and_name", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "ssh_public_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "fingerprint", null: false
    t.string "name", null: false
    t.text "public_key", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["fingerprint"], name: "index_ssh_public_keys_on_fingerprint", unique: true
    t.index ["user_id"], name: "index_ssh_public_keys_on_user_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.bigint "plan_id", null: false
    t.integer "status", default: 0, null: false
    t.string "stripe_subscription_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["plan_id"], name: "index_subscriptions_on_plan_id"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "team_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "role", default: 0, null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id"], name: "index_team_memberships_on_team_id"
    t.index ["user_id", "team_id"], name: "index_team_memberships_on_user_id_and_team_id", unique: true
    t.index ["user_id"], name: "index_team_memberships_on_user_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_teams_on_name", unique: true
    t.index ["owner_id"], name: "index_teams_on_owner_id"
  end

  create_table "usage_events", force: :cascade do |t|
    t.bigint "app_record_id"
    t.datetime "created_at", null: false
    t.string "event_type"
    t.json "metadata"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["app_record_id"], name: "index_usage_events_on_app_record_id"
    t.index ["user_id", "created_at"], name: "index_usage_events_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_usage_events_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "billing_grace_period_ends_at"
    t.integer "billing_status", default: 0, null: false
    t.integer "consumed_timestep"
    t.datetime "created_at", null: false
    t.string "currency", default: "usd"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.bigint "github_installation_id"
    t.string "github_username"
    t.string "locale", default: "en"
    t.string "name"
    t.boolean "otp_required_for_login", default: false, null: false
    t.string "otp_secret"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "role", default: 0, null: false
    t.string "stripe_customer_id"
    t.string "stripe_payment_method_id"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["github_installation_id"], name: "index_users_on_github_installation_id"
    t.index ["otp_secret"], name: "index_users_on_otp_secret", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "activities", "teams"
  add_foreign_key "activities", "users"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "app_databases", "app_records"
  add_foreign_key "app_databases", "database_services"
  add_foreign_key "app_records", "servers"
  add_foreign_key "app_records", "teams"
  add_foreign_key "app_records", "users", column: "created_by_id"
  add_foreign_key "backup_destinations", "servers"
  add_foreign_key "backups", "backup_destinations"
  add_foreign_key "backups", "database_services"
  add_foreign_key "certificates", "domains"
  add_foreign_key "cloud_credentials", "teams"
  add_foreign_key "database_services", "servers"
  add_foreign_key "deploys", "app_records"
  add_foreign_key "device_tokens", "users"
  add_foreign_key "domains", "app_records"
  add_foreign_key "dyno_allocations", "app_records"
  add_foreign_key "dyno_allocations", "dyno_tiers"
  add_foreign_key "env_vars", "app_records"
  add_foreign_key "invoices", "users"
  add_foreign_key "metrics", "app_records"
  add_foreign_key "notifications", "app_records"
  add_foreign_key "notifications", "teams"
  add_foreign_key "process_scales", "app_records"
  add_foreign_key "releases", "app_records"
  add_foreign_key "releases", "deploys"
  add_foreign_key "resource_usages", "users"
  add_foreign_key "servers", "teams"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "ssh_public_keys", "users"
  add_foreign_key "subscriptions", "plans"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "team_memberships", "teams"
  add_foreign_key "team_memberships", "users"
  add_foreign_key "teams", "users", column: "owner_id"
  add_foreign_key "usage_events", "app_records"
  add_foreign_key "usage_events", "users"
end
