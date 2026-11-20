SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuidv7(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uuidv7() RETURNS uuid
    LANGUAGE sql
    AS $$
  SELECT encode(
    set_bit(
      set_bit(
        overlay(uuid_send(gen_random_uuid())
                placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
                from 1 for 6),
        52, 1),
      53, 1),
    'hex')::uuid;
$$;


--
-- Name: wokku_block_activity_mutation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.wokku_block_activity_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'activities is append-only (attempted %)', TG_OP
    USING ERRCODE = '42501';
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: acme_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.acme_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    private_key_pem text NOT NULL,
    kid character varying,
    directory character varying NOT NULL,
    contact character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: activities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activities (
    action character varying NOT NULL,
    target_type character varying,
    target_name character varying,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    team_id uuid NOT NULL,
    target_id uuid
);


--
-- Name: activity_digests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity_digests (
    date date NOT NULL,
    row_count integer DEFAULT 0 NOT NULL,
    chain_hash character varying NOT NULL,
    prev_hash character varying,
    min_activity_id integer,
    max_activity_id integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL
);


--
-- Name: alert_mutes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alert_mutes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    app_record_id uuid,
    event character varying,
    expires_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: api_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_tokens (
    token_digest character varying NOT NULL,
    name character varying,
    last_used_at timestamp(6) without time zone,
    expires_at timestamp(6) without time zone,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    scope character varying DEFAULT 'full'::character varying NOT NULL,
    CONSTRAINT api_tokens_scope_check CHECK (((scope)::text = ANY ((ARRAY['read'::character varying, 'full'::character varying])::text[])))
);


--
-- Name: app_databases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_databases (
    alias_name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    database_service_id uuid NOT NULL,
    app_record_id uuid NOT NULL
);


--
-- Name: app_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_records (
    name character varying NOT NULL,
    status integer DEFAULT 0,
    deploy_branch character varying DEFAULT 'main'::character varying,
    synced_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    git_repository_url character varying,
    github_repo_full_name character varying,
    github_webhook_secret character varying,
    is_preview boolean DEFAULT false NOT NULL,
    pr_number integer,
    git_provider character varying,
    git_repo_full_name character varying,
    git_webhook_secret character varying,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    server_id uuid NOT NULL,
    parent_app_id uuid,
    created_by_id uuid NOT NULL,
    team_id uuid NOT NULL,
    live_cpu_pct numeric(6,2),
    live_mem_used_mb integer,
    live_mem_limit_mb integer,
    live_container_count integer,
    live_metrics_at timestamp(6) without time zone,
    pending_action character varying,
    preview_enabled boolean DEFAULT false NOT NULL,
    database_strategy character varying DEFAULT 'empty'::character varying NOT NULL,
    billing_exempt boolean DEFAULT false NOT NULL,
    last_commit_sha character varying,
    last_commit_at timestamp(6) without time zone,
    preview_comment_id bigint,
    preview_comment_mr_iid integer,
    cloudflare_proxied boolean DEFAULT false NOT NULL,
    box_size character varying,
    enabled_shared_engines character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    vitals_ingest_token character varying,
    uptime_status character varying DEFAULT 'unknown'::character varying NOT NULL,
    uptime_failures integer DEFAULT 0 NOT NULL,
    last_uptime_check_at timestamp(6) without time zone,
    wokkud_routed boolean DEFAULT false NOT NULL,
    container_port integer DEFAULT 5000 NOT NULL,
    wokkud_git boolean DEFAULT false NOT NULL,
    wokkud_lifecycle boolean DEFAULT false NOT NULL,
    swarm_port integer,
    live_containers jsonb,
    live_containers_at timestamp(6) without time zone,
    wokkud_native boolean DEFAULT false NOT NULL,
    storage_mounts jsonb DEFAULT '[]'::jsonb NOT NULL,
    healthcheck_json jsonb,
    deploy_locked_at timestamp(6) without time zone,
    https_redirect boolean DEFAULT true NOT NULL,
    maintenance_mode boolean DEFAULT false NOT NULL,
    volume_disk_gb integer DEFAULT 0 NOT NULL,
    last_request_at timestamp(6) without time zone,
    request_count_seen bigint
);


--
-- Name: app_transfers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_transfers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    from_user_id uuid NOT NULL,
    to_user_id uuid NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    accepted_at timestamp(6) without time zone,
    declined_at timestamp(6) without time zone,
    cancelled_at timestamp(6) without time zone,
    note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: backup_destinations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.backup_destinations (
    provider character varying DEFAULT 's3'::character varying,
    endpoint_url character varying,
    bucket character varying NOT NULL,
    region character varying DEFAULT 'us-east-1'::character varying,
    access_key_id character varying,
    secret_access_key character varying,
    path_prefix character varying DEFAULT 'wokku-backups'::character varying,
    retention_days integer DEFAULT 30,
    enabled boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    server_id uuid NOT NULL
);


--
-- Name: backups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.backups (
    s3_key character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying,
    size_bytes bigint,
    error_message text,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    backup_destination_id uuid NOT NULL,
    database_service_id uuid,
    encrypted boolean DEFAULT false NOT NULL,
    kind integer DEFAULT 0 NOT NULL,
    mount_path character varying,
    app_record_id uuid
);


--
-- Name: box_addons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.box_addons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    team_id uuid NOT NULL,
    invoice_id uuid,
    size character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    price_idr integer DEFAULT 0 NOT NULL,
    price_usd_cents integer DEFAULT 0 NOT NULL,
    activated_at timestamp(6) without time zone,
    ends_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: certificates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.certificates (
    expires_at timestamp(6) without time zone,
    auto_renew boolean DEFAULT true,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    domain_id uuid NOT NULL
);


--
-- Name: cloud_credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cloud_credentials (
    provider character varying NOT NULL,
    name character varying,
    api_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    team_id uuid NOT NULL
);


--
-- Name: crash_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.crash_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    container_id character varying NOT NULL,
    exit_code integer,
    oom_killed boolean DEFAULT false NOT NULL,
    exited_at timestamp(6) without time zone NOT NULL,
    log_excerpt text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: database_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.database_services (
    service_type character varying,
    name character varying,
    status integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    tier_name character varying DEFAULT 'basic'::character varying NOT NULL,
    shared boolean DEFAULT false NOT NULL,
    over_quota_at timestamp(6) without time zone,
    connection_limit integer,
    storage_mb_quota integer,
    shared_role_name character varying,
    shared_db_name character varying,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    parent_service_id uuid,
    server_id uuid NOT NULL,
    live_db_bytes bigint,
    live_mem_used_mb integer,
    live_metrics_at timestamp(6) without time zone,
    creator_id uuid,
    last_error text,
    pending_destroy_at timestamp(6) without time zone,
    upgrade_source_id uuid,
    wokkud_managed boolean DEFAULT false NOT NULL,
    dsn text,
    cpu numeric(4,2),
    memory_mb integer,
    disk_gb integer
);


--
-- Name: database_stats_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.database_stats_snapshots (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    database_service_id uuid NOT NULL,
    recorded_at timestamp(6) without time zone NOT NULL,
    active_connections integer,
    max_connections integer,
    db_size_bytes bigint,
    cache_hit_ratio double precision,
    top_queries jsonb DEFAULT '[]'::jsonb,
    raw_info jsonb DEFAULT '{}'::jsonb,
    collected_via character varying,
    collection_error character varying,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: deploys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deploys (
    status integer DEFAULT 0,
    commit_sha character varying,
    log text,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL,
    release_id uuid,
    archive_key character varying,
    image_ref character varying,
    builder character varying,
    build_picked_up_at timestamp(6) without time zone,
    build_finished_at timestamp(6) without time zone,
    build_error text,
    formation_json jsonb,
    run_after_deploy character varying
);


--
-- Name: dev_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dev_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    app_record_id uuid NOT NULL,
    ssh_principal character varying NOT NULL,
    db_remote_host character varying NOT NULL,
    db_remote_port integer DEFAULT 5432 NOT NULL,
    read_only boolean DEFAULT true NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    revoked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: device_authorizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_authorizations (
    device_code character varying NOT NULL,
    user_code character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    last_polled_at timestamp(6) without time zone,
    plain_token_payload text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    api_token_id uuid,
    user_id uuid
);


--
-- Name: device_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.device_tokens (
    token character varying NOT NULL,
    platform character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    provider character varying DEFAULT 'expo'::character varying NOT NULL,
    api_token_id uuid
);


--
-- Name: domains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domains (
    hostname character varying,
    ssl_enabled boolean DEFAULT false,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    dns_verified boolean DEFAULT false,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL,
    pending_action character varying
);


--
-- Name: dyno_allocations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dyno_allocations (
    process_type character varying NOT NULL,
    count integer DEFAULT 1 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL,
    dyno_tier_id uuid,
    cpu numeric(4,2),
    memory_mb integer
);


--
-- Name: dyno_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dyno_tiers (
    name character varying NOT NULL,
    memory_mb integer NOT NULL,
    cpu_shares numeric(4,2) DEFAULT 0.0 NOT NULL,
    price_cents_per_month integer,
    sleeps boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    price_cents_per_hour numeric(10,4) DEFAULT 0.0 NOT NULL,
    storage_mb integer DEFAULT 0 NOT NULL,
    max_per_user integer,
    scalable boolean DEFAULT false NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    monthly_price_cents integer DEFAULT 0 NOT NULL
);


--
-- Name: env_vars; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.env_vars (
    key character varying,
    value text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL,
    scope character varying DEFAULT 'both'::character varying NOT NULL
);


--
-- Name: feedback_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying,
    email character varying,
    message text NOT NULL,
    page character varying,
    user_agent character varying,
    user_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: incidents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.incidents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    server_id uuid,
    app_record_id uuid,
    reason character varying NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    resolved_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT incidents_exactly_one_subject CHECK (((server_id IS NULL) <> (app_record_id IS NULL)))
);


--
-- Name: invoices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invoices (
    amount_cents integer,
    status integer DEFAULT 0,
    stripe_invoice_id character varying,
    paid_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ipaymu_transaction_id character varying,
    ipaymu_payment_url character varying,
    payment_method character varying,
    due_date timestamp(6) without time zone,
    reference_id character varying,
    amount_idr integer DEFAULT 0,
    period_label character varying,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    plan_id uuid,
    period_start date,
    period_end date,
    kind integer DEFAULT 0 NOT NULL,
    team_id uuid
);


--
-- Name: known_devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.known_devices (
    ip character varying NOT NULL,
    user_agent_hash character varying NOT NULL,
    user_agent_label character varying,
    first_seen_at timestamp(6) without time zone NOT NULL,
    last_seen_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL
);


--
-- Name: leads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leads (
    id bigint NOT NULL,
    email character varying,
    pain_text text NOT NULL,
    ip character varying,
    user_agent character varying(512),
    utm_source character varying,
    utm_medium character varying,
    utm_campaign character varying,
    utm_content character varying,
    utm_term character varying,
    channel character varying,
    user_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: leads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.leads_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: leads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.leads_id_seq OWNED BY public.leads.id;


--
-- Name: lifecycle_ops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lifecycle_ops (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    server_id uuid NOT NULL,
    kind character varying NOT NULL,
    params jsonb DEFAULT '{}'::jsonb NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    log text,
    result jsonb,
    error character varying,
    error_code character varying,
    claimed_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    server_id uuid NOT NULL,
    app_record_id uuid,
    container character varying NOT NULL,
    ts timestamp(6) without time zone NOT NULL,
    level character varying,
    line text NOT NULL,
    ingested_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: metric_hourly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metric_hourly (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    hour_start timestamp(6) without time zone NOT NULL,
    avg_cpu_percent double precision,
    max_cpu_percent double precision,
    avg_memory_usage bigint,
    max_memory_usage bigint,
    memory_limit bigint,
    sample_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: metrics; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.metrics (
    cpu_percent double precision,
    memory_usage bigint,
    memory_limit bigint,
    recorded_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL
);


--
-- Name: mobile_auth_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mobile_auth_codes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    code_digest character varying NOT NULL,
    code_challenge character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    used_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    channel integer,
    events json,
    config json,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    team_id uuid NOT NULL,
    app_record_id uuid
);


--
-- Name: object_storage_buckets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.object_storage_buckets (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid,
    team_id uuid NOT NULL,
    name character varying NOT NULL,
    access_key character varying NOT NULL,
    secret_key text NOT NULL,
    quota_gb integer NOT NULL,
    used_bytes bigint DEFAULT 0 NOT NULL,
    used_at timestamp(6) without time zone,
    warned_at timestamp(6) without time zone,
    status character varying DEFAULT 'provisioning'::character varying NOT NULL,
    last_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    pending_revoke_access_key character varying
);


--
-- Name: oss_revenue_shares; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.oss_revenue_shares (
    template_slug character varying NOT NULL,
    funding_url character varying,
    total_cents integer DEFAULT 0,
    paid_cents integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL
);


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plans (
    name character varying NOT NULL,
    max_apps integer DEFAULT 0 NOT NULL,
    max_dynos integer DEFAULT 0,
    max_databases integer DEFAULT 0,
    price_cents_per_month integer DEFAULT 0,
    stripe_price_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    key character varying DEFAULT ''::character varying NOT NULL,
    price_usd_cents integer DEFAULT 0 NOT NULL,
    price_idr integer DEFAULT 0 NOT NULL,
    seats_included integer DEFAULT 1 NOT NULL,
    extra_seat_usd_cents integer DEFAULT 0 NOT NULL,
    box_quotas jsonb DEFAULT '{}'::jsonb NOT NULL,
    addons_available jsonb DEFAULT '{}'::jsonb NOT NULL,
    backup_policy character varying DEFAULT 'manual'::character varying NOT NULL,
    backup_retention_days integer DEFAULT 0 NOT NULL,
    support_level character varying DEFAULT 'chatbot'::character varying NOT NULL,
    pro_features jsonb DEFAULT '[]'::jsonb NOT NULL,
    log_retention_days integer DEFAULT 1 NOT NULL,
    sample_retention_hours integer DEFAULT 24 NOT NULL,
    metric_high_res_days integer DEFAULT 1 NOT NULL,
    metric_aggregate_retention_days integer DEFAULT 7 NOT NULL,
    db_bundle_mb integer DEFAULT 100 NOT NULL,
    redis_bundle_mb integer DEFAULT 25 NOT NULL,
    minio_bundle_gb integer DEFAULT 1 NOT NULL,
    extra_seat_idr integer DEFAULT 0 NOT NULL,
    shared_pg_mb_per_tenant integer DEFAULT 50 NOT NULL,
    shared_redis_mb_per_tenant integer DEFAULT 10 NOT NULL,
    shared_memcached_mb_per_tenant integer DEFAULT 16 NOT NULL,
    shared_rabbitmq_msg_per_tenant integer DEFAULT 10000 NOT NULL,
    shared_meilisearch_mb_per_tenant integer DEFAULT 50 NOT NULL,
    dedicated_pg_slots integer DEFAULT 0 NOT NULL,
    dedicated_pg_size_mb integer DEFAULT 0 NOT NULL,
    dedicated_redis_slots integer DEFAULT 0 NOT NULL,
    dedicated_redis_size_mb integer DEFAULT 0 NOT NULL
);


--
-- Name: preview_dns_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.preview_dns_records (
    id bigint NOT NULL,
    app_record_id uuid NOT NULL,
    hostname character varying NOT NULL,
    cloudflare_record_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: preview_dns_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.preview_dns_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: preview_dns_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.preview_dns_records_id_seq OWNED BY public.preview_dns_records.id;


--
-- Name: process_scales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.process_scales (
    process_type character varying,
    count integer DEFAULT 1,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL
);


--
-- Name: push_tickets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.push_tickets (
    ticket_id character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying,
    checked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    device_token_id uuid NOT NULL
);


--
-- Name: releases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.releases (
    version integer,
    description character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL,
    deploy_id uuid
);


--
-- Name: request_aggregates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_aggregates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    bucket_start timestamp(6) without time zone NOT NULL,
    req_count integer DEFAULT 0 NOT NULL,
    p50_ms integer,
    p95_ms integer,
    error_4xx integer DEFAULT 0 NOT NULL,
    error_5xx integer DEFAULT 0 NOT NULL,
    bytes_sent_total bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: request_samples; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_samples (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    server_id uuid NOT NULL,
    app_record_id uuid,
    ts timestamp(6) without time zone NOT NULL,
    method character varying(8),
    path character varying(2048),
    status integer,
    response_time_ms integer,
    bytes_sent bigint,
    remote_addr character varying(64),
    ingested_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: restore_drills; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restore_drills (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    engine character varying NOT NULL,
    database_service_id uuid,
    backup_id uuid,
    status integer DEFAULT 0 NOT NULL,
    live_tables bigint,
    live_rows bigint,
    restored_tables bigint,
    restored_rows bigint,
    rto_ms integer,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: scheduled_task_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheduled_task_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    scheduled_task_id uuid NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    finished_at timestamp(6) without time zone,
    exit_code integer,
    skipped_reason character varying,
    log_excerpt text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: scheduled_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.scheduled_tasks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    command text NOT NULL,
    schedule character varying NOT NULL,
    description character varying,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: servers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.servers (
    name character varying NOT NULL,
    host character varying NOT NULL,
    port integer DEFAULT 22,
    ssh_user character varying DEFAULT 'dokku'::character varying,
    ssh_private_key text,
    status integer DEFAULT 0,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    capacity_total_mb integer DEFAULT 0,
    region character varying,
    cloud_provider character varying,
    cloud_server_id character varying,
    monthly_cost_cents integer,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    team_id uuid,
    live_cpu_pct numeric(6,2),
    live_mem_used_mb integer,
    live_mem_total_mb integer,
    live_container_count integer,
    live_metrics_at timestamp(6) without time zone,
    docker_status character varying,
    docker_status_checked_at timestamp(6) without time zone,
    ingest_token character varying,
    heartbeat_at timestamp(6) without time zone,
    heartbeat_status character varying DEFAULT 'unknown'::character varying NOT NULL,
    vitals jsonb DEFAULT '{}'::jsonb NOT NULL,
    agent_version character varying,
    wokkud_builds_enabled boolean DEFAULT false NOT NULL,
    wokkud_router_enabled boolean DEFAULT false NOT NULL,
    wokkud_services_enabled boolean DEFAULT false NOT NULL,
    wokkud_cron_enabled boolean DEFAULT false NOT NULL,
    ssh_alerted_at timestamp(6) without time zone,
    ingest_token_digest character varying
);


--
-- Name: service_ops; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_ops (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    database_service_id uuid NOT NULL,
    server_id uuid NOT NULL,
    kind character varying NOT NULL,
    params jsonb DEFAULT '{}'::jsonb NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    log text,
    result jsonb,
    error character varying,
    error_code character varying,
    claimed_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: service_tiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.service_tiers (
    name character varying NOT NULL,
    service_type character varying NOT NULL,
    price_cents_per_hour numeric(10,4) DEFAULT 0.0 NOT NULL,
    spec jsonb DEFAULT '{}'::jsonb,
    available boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    monthly_price_cents integer DEFAULT 0 NOT NULL
);


--
-- Name: solid_queue_blocked_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_blocked_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    concurrency_key character varying NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_blocked_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_blocked_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_blocked_executions_id_seq OWNED BY public.solid_queue_blocked_executions.id;


--
-- Name: solid_queue_claimed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_claimed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    process_id bigint,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_claimed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_claimed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_claimed_executions_id_seq OWNED BY public.solid_queue_claimed_executions.id;


--
-- Name: solid_queue_failed_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_failed_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_failed_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_failed_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_failed_executions_id_seq OWNED BY public.solid_queue_failed_executions.id;


--
-- Name: solid_queue_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_jobs (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    class_name character varying NOT NULL,
    arguments text,
    priority integer DEFAULT 0 NOT NULL,
    active_job_id character varying,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    concurrency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_jobs_id_seq OWNED BY public.solid_queue_jobs.id;


--
-- Name: solid_queue_pauses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_pauses (
    id bigint NOT NULL,
    queue_name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_pauses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_pauses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_pauses_id_seq OWNED BY public.solid_queue_pauses.id;


--
-- Name: solid_queue_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_processes (
    id bigint NOT NULL,
    kind character varying NOT NULL,
    last_heartbeat_at timestamp(6) without time zone NOT NULL,
    supervisor_id bigint,
    pid integer NOT NULL,
    hostname character varying,
    metadata text,
    created_at timestamp(6) without time zone NOT NULL,
    name character varying NOT NULL
);


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_processes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_processes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_processes_id_seq OWNED BY public.solid_queue_processes.id;


--
-- Name: solid_queue_ready_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_ready_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_ready_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_ready_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_ready_executions_id_seq OWNED BY public.solid_queue_ready_executions.id;


--
-- Name: solid_queue_recurring_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    task_key character varying NOT NULL,
    run_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_executions_id_seq OWNED BY public.solid_queue_recurring_executions.id;


--
-- Name: solid_queue_recurring_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_recurring_tasks (
    id bigint NOT NULL,
    key character varying NOT NULL,
    schedule character varying NOT NULL,
    command character varying(2048),
    class_name character varying,
    arguments text,
    queue_name character varying,
    priority integer DEFAULT 0,
    static boolean DEFAULT true NOT NULL,
    description text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_recurring_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_recurring_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_recurring_tasks_id_seq OWNED BY public.solid_queue_recurring_tasks.id;


--
-- Name: solid_queue_scheduled_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_scheduled_executions (
    id bigint NOT NULL,
    job_id bigint NOT NULL,
    queue_name character varying NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    scheduled_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_scheduled_executions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_scheduled_executions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_scheduled_executions_id_seq OWNED BY public.solid_queue_scheduled_executions.id;


--
-- Name: solid_queue_semaphores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.solid_queue_semaphores (
    id bigint NOT NULL,
    key character varying NOT NULL,
    value integer DEFAULT 1 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.solid_queue_semaphores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: solid_queue_semaphores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.solid_queue_semaphores_id_seq OWNED BY public.solid_queue_semaphores.id;


--
-- Name: ssh_public_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ssh_public_keys (
    name character varying NOT NULL,
    public_key text NOT NULL,
    fingerprint character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL
);


--
-- Name: storage_backup_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.storage_backup_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    server_id uuid NOT NULL,
    kind character varying NOT NULL,
    status character varying NOT NULL,
    objects bigint,
    bytes bigint,
    duration_s integer,
    error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    status integer DEFAULT 0 NOT NULL,
    stripe_subscription_id character varying,
    current_period_end timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    plan_id uuid NOT NULL,
    user_id uuid NOT NULL,
    team_id uuid
);


--
-- Name: swarm_port_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.swarm_port_seq
    START WITH 20000
    INCREMENT BY 1
    MINVALUE 20000
    MAXVALUE 29999
    CACHE 1;


--
-- Name: team_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_memberships (
    role integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    team_id uuid NOT NULL
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    owner_id uuid NOT NULL,
    plan_id uuid,
    trial_ends_at timestamp(6) without time zone,
    kind integer,
    slug character varying,
    billing_anchor_date date,
    payment_method_type character varying DEFAULT 'none'::character varying NOT NULL
);


--
-- Name: tunnel_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tunnel_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    app_record_id uuid,
    server_id uuid,
    subdomain character varying NOT NULL,
    token_digest character varying NOT NULL,
    plan_at_creation character varying NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    started_at timestamp(6) without time zone,
    closed_at timestamp(6) without time zone,
    bytes_in bigint DEFAULT 0 NOT NULL,
    bytes_out bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: site_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.site_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    body_scripts text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: update_statuses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.update_statuses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    latest_version character varying,
    notified_version character varying,
    checked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: usage_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_events (
    event_type character varying,
    metadata json,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    app_record_id uuid
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    role integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    stripe_customer_id character varying,
    stripe_payment_method_id character varying,
    billing_grace_period_ends_at timestamp(6) without time zone,
    billing_status integer DEFAULT 0 NOT NULL,
    github_installation_id bigint,
    github_username character varying,
    provider character varying,
    uid character varying,
    avatar_url character varying,
    name character varying,
    currency character varying DEFAULT 'usd'::character varying,
    locale character varying DEFAULT 'en'::character varying,
    otp_secret character varying,
    consumed_timestep integer,
    otp_required_for_login boolean DEFAULT false NOT NULL,
    failed_attempts integer DEFAULT 0 NOT NULL,
    unlock_token character varying,
    locked_at timestamp(6) without time zone,
    payment_method_type character varying DEFAULT 'none'::character varying,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    deleted_at timestamp(6) without time zone,
    deletion_scheduled_at timestamp(6) without time zone,
    gitlab_access_token character varying,
    gitlab_refresh_token character varying,
    gitlab_token_expires_at timestamp(6) without time zone,
    bitbucket_access_token character varying,
    bitbucket_refresh_token character varying,
    bitbucket_token_expires_at timestamp(6) without time zone,
    onboarding_status integer DEFAULT 0 NOT NULL,
    onboarding_step integer DEFAULT 0 NOT NULL,
    plan_id uuid NOT NULL,
    pending_plan_id uuid,
    plan_changes_at timestamp(6) without time zone,
    trial_ends_at timestamp(6) without time zone,
    billing_anchor_date date,
    apple_uid character varying,
    apple_refresh_token text,
    apple_token_client_id character varying,
    email_provider_verified boolean DEFAULT false NOT NULL,
    otp_backup_codes character varying[]
);


--
-- Name: vitals_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vitals_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    metric character varying NOT NULL,
    value_ms double precision NOT NULL,
    received_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: vitals_hourly_rollups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vitals_hourly_rollups (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    app_record_id uuid NOT NULL,
    bucketed_at timestamp(6) without time zone NOT NULL,
    metric character varying NOT NULL,
    p50 double precision NOT NULL,
    p75 double precision NOT NULL,
    p95 double precision NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: wildcard_certificates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wildcard_certificates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    fullchain_pem text NOT NULL,
    key_pem text NOT NULL,
    sans character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    issued_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: leads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads ALTER COLUMN id SET DEFAULT nextval('public.leads_id_seq'::regclass);


--
-- Name: preview_dns_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preview_dns_records ALTER COLUMN id SET DEFAULT nextval('public.preview_dns_records_id_seq'::regclass);


--
-- Name: solid_queue_blocked_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_blocked_executions_id_seq'::regclass);


--
-- Name: solid_queue_claimed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_claimed_executions_id_seq'::regclass);


--
-- Name: solid_queue_failed_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_failed_executions_id_seq'::regclass);


--
-- Name: solid_queue_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_jobs_id_seq'::regclass);


--
-- Name: solid_queue_pauses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_pauses_id_seq'::regclass);


--
-- Name: solid_queue_processes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_processes_id_seq'::regclass);


--
-- Name: solid_queue_ready_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_ready_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_executions_id_seq'::regclass);


--
-- Name: solid_queue_recurring_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_recurring_tasks_id_seq'::regclass);


--
-- Name: solid_queue_scheduled_executions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_scheduled_executions_id_seq'::regclass);


--
-- Name: solid_queue_semaphores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores ALTER COLUMN id SET DEFAULT nextval('public.solid_queue_semaphores_id_seq'::regclass);


--
-- Name: acme_accounts acme_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.acme_accounts
    ADD CONSTRAINT acme_accounts_pkey PRIMARY KEY (id);


--
-- Name: activities activities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT activities_pkey PRIMARY KEY (id);


--
-- Name: activity_digests activity_digests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity_digests
    ADD CONSTRAINT activity_digests_pkey PRIMARY KEY (id);


--
-- Name: alert_mutes alert_mutes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_mutes
    ADD CONSTRAINT alert_mutes_pkey PRIMARY KEY (id);


--
-- Name: api_tokens api_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT api_tokens_pkey PRIMARY KEY (id);


--
-- Name: app_databases app_databases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_databases
    ADD CONSTRAINT app_databases_pkey PRIMARY KEY (id);


--
-- Name: app_records app_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_records
    ADD CONSTRAINT app_records_pkey PRIMARY KEY (id);


--
-- Name: app_transfers app_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_transfers
    ADD CONSTRAINT app_transfers_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: backup_destinations backup_destinations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.backup_destinations
    ADD CONSTRAINT backup_destinations_pkey PRIMARY KEY (id);


--
-- Name: backups backups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.backups
    ADD CONSTRAINT backups_pkey PRIMARY KEY (id);


--
-- Name: box_addons box_addons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.box_addons
    ADD CONSTRAINT box_addons_pkey PRIMARY KEY (id);


--
-- Name: certificates certificates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT certificates_pkey PRIMARY KEY (id);


--
-- Name: cloud_credentials cloud_credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cloud_credentials
    ADD CONSTRAINT cloud_credentials_pkey PRIMARY KEY (id);


--
-- Name: crash_events crash_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crash_events
    ADD CONSTRAINT crash_events_pkey PRIMARY KEY (id);


--
-- Name: database_services database_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_services
    ADD CONSTRAINT database_services_pkey PRIMARY KEY (id);


--
-- Name: database_stats_snapshots database_stats_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_stats_snapshots
    ADD CONSTRAINT database_stats_snapshots_pkey PRIMARY KEY (id);


--
-- Name: deploys deploys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deploys
    ADD CONSTRAINT deploys_pkey PRIMARY KEY (id);


--
-- Name: dev_sessions dev_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dev_sessions
    ADD CONSTRAINT dev_sessions_pkey PRIMARY KEY (id);


--
-- Name: device_authorizations device_authorizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_authorizations
    ADD CONSTRAINT device_authorizations_pkey PRIMARY KEY (id);


--
-- Name: device_tokens device_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT device_tokens_pkey PRIMARY KEY (id);


--
-- Name: domains domains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains
    ADD CONSTRAINT domains_pkey PRIMARY KEY (id);


--
-- Name: dyno_allocations dyno_allocations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dyno_allocations
    ADD CONSTRAINT dyno_allocations_pkey PRIMARY KEY (id);


--
-- Name: dyno_tiers dyno_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dyno_tiers
    ADD CONSTRAINT dyno_tiers_pkey PRIMARY KEY (id);


--
-- Name: env_vars env_vars_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_vars
    ADD CONSTRAINT env_vars_pkey PRIMARY KEY (id);


--
-- Name: feedback_entries feedback_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_entries
    ADD CONSTRAINT feedback_entries_pkey PRIMARY KEY (id);


--
-- Name: incidents incidents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT incidents_pkey PRIMARY KEY (id);


--
-- Name: invoices invoices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT invoices_pkey PRIMARY KEY (id);


--
-- Name: known_devices known_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_devices
    ADD CONSTRAINT known_devices_pkey PRIMARY KEY (id);


--
-- Name: leads leads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT leads_pkey PRIMARY KEY (id);


--
-- Name: lifecycle_ops lifecycle_ops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lifecycle_ops
    ADD CONSTRAINT lifecycle_ops_pkey PRIMARY KEY (id);


--
-- Name: logs logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT logs_pkey PRIMARY KEY (id);


--
-- Name: metric_hourly metric_hourly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_hourly
    ADD CONSTRAINT metric_hourly_pkey PRIMARY KEY (id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);


--
-- Name: mobile_auth_codes mobile_auth_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mobile_auth_codes
    ADD CONSTRAINT mobile_auth_codes_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: object_storage_buckets object_storage_buckets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.object_storage_buckets
    ADD CONSTRAINT object_storage_buckets_pkey PRIMARY KEY (id);


--
-- Name: oss_revenue_shares oss_revenue_shares_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.oss_revenue_shares
    ADD CONSTRAINT oss_revenue_shares_pkey PRIMARY KEY (id);


--
-- Name: plans plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: preview_dns_records preview_dns_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preview_dns_records
    ADD CONSTRAINT preview_dns_records_pkey PRIMARY KEY (id);


--
-- Name: process_scales process_scales_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.process_scales
    ADD CONSTRAINT process_scales_pkey PRIMARY KEY (id);


--
-- Name: push_tickets push_tickets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tickets
    ADD CONSTRAINT push_tickets_pkey PRIMARY KEY (id);


--
-- Name: releases releases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT releases_pkey PRIMARY KEY (id);


--
-- Name: request_aggregates request_aggregates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_aggregates
    ADD CONSTRAINT request_aggregates_pkey PRIMARY KEY (id);


--
-- Name: request_samples request_samples_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_samples
    ADD CONSTRAINT request_samples_pkey PRIMARY KEY (id);


--
-- Name: restore_drills restore_drills_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restore_drills
    ADD CONSTRAINT restore_drills_pkey PRIMARY KEY (id);


--
-- Name: scheduled_task_runs scheduled_task_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_task_runs
    ADD CONSTRAINT scheduled_task_runs_pkey PRIMARY KEY (id);


--
-- Name: scheduled_tasks scheduled_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_tasks
    ADD CONSTRAINT scheduled_tasks_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: servers servers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servers
    ADD CONSTRAINT servers_pkey PRIMARY KEY (id);


--
-- Name: service_ops service_ops_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_ops
    ADD CONSTRAINT service_ops_pkey PRIMARY KEY (id);


--
-- Name: service_tiers service_tiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_tiers
    ADD CONSTRAINT service_tiers_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_blocked_executions solid_queue_blocked_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT solid_queue_blocked_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_claimed_executions solid_queue_claimed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT solid_queue_claimed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_failed_executions solid_queue_failed_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT solid_queue_failed_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_jobs solid_queue_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_jobs
    ADD CONSTRAINT solid_queue_jobs_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_pauses solid_queue_pauses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_pauses
    ADD CONSTRAINT solid_queue_pauses_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_processes solid_queue_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_processes
    ADD CONSTRAINT solid_queue_processes_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_ready_executions solid_queue_ready_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT solid_queue_ready_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_executions solid_queue_recurring_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT solid_queue_recurring_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_recurring_tasks solid_queue_recurring_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_tasks
    ADD CONSTRAINT solid_queue_recurring_tasks_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_scheduled_executions solid_queue_scheduled_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT solid_queue_scheduled_executions_pkey PRIMARY KEY (id);


--
-- Name: solid_queue_semaphores solid_queue_semaphores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_semaphores
    ADD CONSTRAINT solid_queue_semaphores_pkey PRIMARY KEY (id);


--
-- Name: ssh_public_keys ssh_public_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ssh_public_keys
    ADD CONSTRAINT ssh_public_keys_pkey PRIMARY KEY (id);


--
-- Name: storage_backup_runs storage_backup_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.storage_backup_runs
    ADD CONSTRAINT storage_backup_runs_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: team_memberships team_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT team_memberships_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: tunnel_sessions tunnel_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tunnel_sessions
    ADD CONSTRAINT tunnel_sessions_pkey PRIMARY KEY (id);


--
-- Name: site_settings site_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.site_settings
    ADD CONSTRAINT site_settings_pkey PRIMARY KEY (id);


--
-- Name: update_statuses update_statuses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.update_statuses
    ADD CONSTRAINT update_statuses_pkey PRIMARY KEY (id);


--
-- Name: usage_events usage_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_events
    ADD CONSTRAINT usage_events_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: vitals_events vitals_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vitals_events
    ADD CONSTRAINT vitals_events_pkey PRIMARY KEY (id);


--
-- Name: vitals_hourly_rollups vitals_hourly_rollups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vitals_hourly_rollups
    ADD CONSTRAINT vitals_hourly_rollups_pkey PRIMARY KEY (id);


--
-- Name: wildcard_certificates wildcard_certificates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wildcard_certificates
    ADD CONSTRAINT wildcard_certificates_pkey PRIMARY KEY (id);


--
-- Name: idx_db_stats_recorded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_db_stats_recorded ON public.database_stats_snapshots USING btree (recorded_at DESC);


--
-- Name: idx_db_stats_svc_recorded; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_db_stats_svc_recorded ON public.database_stats_snapshots USING btree (database_service_id, recorded_at DESC);


--
-- Name: idx_dev_sessions_active_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_sessions_active_expiry ON public.dev_sessions USING btree (expires_at) WHERE (revoked_at IS NULL);


--
-- Name: idx_dev_sessions_user_app; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_dev_sessions_user_app ON public.dev_sessions USING btree (user_id, app_record_id);


--
-- Name: idx_logs_app_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_logs_app_ts ON public.logs USING btree (app_record_id, ts DESC);


--
-- Name: idx_logs_server_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_logs_server_ts ON public.logs USING btree (server_id, ts DESC);


--
-- Name: idx_logs_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_logs_ts ON public.logs USING btree (ts DESC);


--
-- Name: idx_metric_hourly_app_hour; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_metric_hourly_app_hour ON public.metric_hourly USING btree (app_record_id, hour_start);


--
-- Name: idx_metric_hourly_hour; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_metric_hourly_hour ON public.metric_hourly USING btree (hour_start DESC);


--
-- Name: idx_req_agg_app_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_req_agg_app_bucket ON public.request_aggregates USING btree (app_record_id, bucket_start);


--
-- Name: idx_req_agg_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_req_agg_bucket ON public.request_aggregates USING btree (bucket_start DESC);


--
-- Name: idx_req_samples_app_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_req_samples_app_ts ON public.request_samples USING btree (app_record_id, ts DESC);


--
-- Name: idx_req_samples_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_req_samples_ts ON public.request_samples USING btree (ts DESC);


--
-- Name: idx_tunnel_sessions_active_expiry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tunnel_sessions_active_expiry ON public.tunnel_sessions USING btree (expires_at) WHERE (closed_at IS NULL);


--
-- Name: idx_tunnel_sessions_active_subdomain; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tunnel_sessions_active_subdomain ON public.tunnel_sessions USING btree (subdomain) WHERE (closed_at IS NULL);


--
-- Name: idx_vitals_events_app_received; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vitals_events_app_received ON public.vitals_events USING btree (app_record_id, received_at);


--
-- Name: idx_vitals_events_received_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vitals_events_received_at ON public.vitals_events USING btree (received_at);


--
-- Name: idx_vitals_rollup_app_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vitals_rollup_app_time ON public.vitals_hourly_rollups USING btree (app_record_id, bucketed_at DESC);


--
-- Name: idx_vitals_rollup_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_vitals_rollup_unique ON public.vitals_hourly_rollups USING btree (app_record_id, bucketed_at, metric);


--
-- Name: index_activities_on_target_type_and_target_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_target_type_and_target_id ON public.activities USING btree (target_type, target_id);


--
-- Name: index_activities_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_team_id ON public.activities USING btree (team_id);


--
-- Name: index_activities_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_activities_on_user_id ON public.activities USING btree (user_id);


--
-- Name: index_activity_digests_on_date; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_activity_digests_on_date ON public.activity_digests USING btree (date);


--
-- Name: index_alert_mutes_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_alert_mutes_on_app_record_id ON public.alert_mutes USING btree (app_record_id);


--
-- Name: index_alert_mutes_on_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_alert_mutes_on_scope ON public.alert_mutes USING btree (user_id, COALESCE(app_record_id, '00000000-0000-0000-0000-000000000000'::uuid), COALESCE(event, ''::character varying));


--
-- Name: index_api_tokens_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_api_tokens_on_token_digest ON public.api_tokens USING btree (token_digest);


--
-- Name: index_api_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_api_tokens_on_user_id ON public.api_tokens USING btree (user_id);


--
-- Name: index_app_databases_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_databases_on_app_record_id ON public.app_databases USING btree (app_record_id);


--
-- Name: index_app_databases_on_database_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_databases_on_database_service_id ON public.app_databases USING btree (database_service_id);


--
-- Name: index_app_records_on_box_size; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_box_size ON public.app_records USING btree (box_size);


--
-- Name: index_app_records_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_created_by_id ON public.app_records USING btree (created_by_id);


--
-- Name: index_app_records_on_github_repo_full_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_github_repo_full_name ON public.app_records USING btree (github_repo_full_name);


--
-- Name: index_app_records_on_is_preview_and_last_commit_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_is_preview_and_last_commit_at ON public.app_records USING btree (is_preview, last_commit_at);


--
-- Name: index_app_records_on_is_preview_and_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_is_preview_and_team_id ON public.app_records USING btree (is_preview, team_id);


--
-- Name: index_app_records_on_parent_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_parent_app_id ON public.app_records USING btree (parent_app_id);


--
-- Name: index_app_records_on_parent_pr_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_app_records_on_parent_pr_unique ON public.app_records USING btree (parent_app_id, pr_number) WHERE (is_preview = true);


--
-- Name: index_app_records_on_provider_and_repo; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_provider_and_repo ON public.app_records USING btree (git_provider, git_repo_full_name);


--
-- Name: index_app_records_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_server_id ON public.app_records USING btree (server_id);


--
-- Name: index_app_records_on_swarm_port; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_app_records_on_swarm_port ON public.app_records USING btree (swarm_port);


--
-- Name: index_app_records_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_team_id ON public.app_records USING btree (team_id);


--
-- Name: index_servers_on_ingest_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_servers_on_ingest_token_digest ON public.servers USING btree (ingest_token_digest);


--
-- Name: index_app_records_on_vitals_ingest_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_app_records_on_vitals_ingest_token ON public.app_records USING btree (vitals_ingest_token) WHERE (vitals_ingest_token IS NOT NULL);


--
-- Name: index_app_transfers_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_transfers_on_app_record_id ON public.app_transfers USING btree (app_record_id);


--
-- Name: index_app_transfers_on_app_record_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_transfers_on_app_record_id_and_status ON public.app_transfers USING btree (app_record_id, status);


--
-- Name: index_app_transfers_on_from_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_transfers_on_from_user_id ON public.app_transfers USING btree (from_user_id);


--
-- Name: index_app_transfers_on_to_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_transfers_on_to_user_id ON public.app_transfers USING btree (to_user_id);


--
-- Name: index_app_transfers_on_to_user_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_transfers_on_to_user_id_and_status ON public.app_transfers USING btree (to_user_id, status);


--
-- Name: index_backup_destinations_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_backup_destinations_on_server_id ON public.backup_destinations USING btree (server_id);


--
-- Name: index_backups_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_backups_on_app_record_id ON public.backups USING btree (app_record_id);


--
-- Name: index_backups_on_backup_destination_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_backups_on_backup_destination_id ON public.backups USING btree (backup_destination_id);


--
-- Name: index_backups_on_database_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_backups_on_database_service_id ON public.backups USING btree (database_service_id);


--
-- Name: index_box_addons_on_invoice_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_box_addons_on_invoice_id ON public.box_addons USING btree (invoice_id);


--
-- Name: index_box_addons_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_box_addons_on_team_id ON public.box_addons USING btree (team_id);


--
-- Name: index_box_addons_on_team_id_and_size_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_box_addons_on_team_id_and_size_and_status ON public.box_addons USING btree (team_id, size, status);


--
-- Name: index_certificates_on_domain_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_certificates_on_domain_id ON public.certificates USING btree (domain_id);


--
-- Name: index_cloud_credentials_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cloud_credentials_on_team_id ON public.cloud_credentials USING btree (team_id);


--
-- Name: index_crash_events_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crash_events_on_app_record_id ON public.crash_events USING btree (app_record_id);


--
-- Name: index_crash_events_on_app_record_id_and_exited_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_crash_events_on_app_record_id_and_exited_at ON public.crash_events USING btree (app_record_id, exited_at);


--
-- Name: index_crash_events_on_container_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_crash_events_on_container_id ON public.crash_events USING btree (container_id);


--
-- Name: index_database_services_on_creator_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_creator_id ON public.database_services USING btree (creator_id);


--
-- Name: index_database_services_on_parent_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_parent_service_id ON public.database_services USING btree (parent_service_id);


--
-- Name: index_database_services_on_pending_destroy_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_pending_destroy_at ON public.database_services USING btree (pending_destroy_at) WHERE (pending_destroy_at IS NOT NULL);


--
-- Name: index_database_services_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_server_id ON public.database_services USING btree (server_id);


--
-- Name: index_database_services_on_shared; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_shared ON public.database_services USING btree (shared);


--
-- Name: index_database_services_on_tier_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_tier_name ON public.database_services USING btree (tier_name);


--
-- Name: index_database_services_on_upgrade_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_upgrade_source_id ON public.database_services USING btree (upgrade_source_id);


--
-- Name: index_database_stats_snapshots_on_database_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_stats_snapshots_on_database_service_id ON public.database_stats_snapshots USING btree (database_service_id);


--
-- Name: index_deploys_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deploys_on_app_record_id ON public.deploys USING btree (app_record_id);


--
-- Name: index_deploys_on_release_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deploys_on_release_id ON public.deploys USING btree (release_id);


--
-- Name: index_dev_sessions_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dev_sessions_on_app_record_id ON public.dev_sessions USING btree (app_record_id);


--
-- Name: index_dev_sessions_on_ssh_principal; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_dev_sessions_on_ssh_principal ON public.dev_sessions USING btree (ssh_principal);


--
-- Name: index_dev_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dev_sessions_on_user_id ON public.dev_sessions USING btree (user_id);


--
-- Name: index_device_authorizations_on_api_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_authorizations_on_api_token_id ON public.device_authorizations USING btree (api_token_id);


--
-- Name: index_device_authorizations_on_device_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_device_authorizations_on_device_code ON public.device_authorizations USING btree (device_code);


--
-- Name: index_device_authorizations_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_authorizations_on_status ON public.device_authorizations USING btree (status);


--
-- Name: index_device_authorizations_on_user_code; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_device_authorizations_on_user_code ON public.device_authorizations USING btree (user_code);


--
-- Name: index_device_authorizations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_authorizations_on_user_id ON public.device_authorizations USING btree (user_id);


--
-- Name: index_device_tokens_on_api_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_tokens_on_api_token_id ON public.device_tokens USING btree (api_token_id);


--
-- Name: index_device_tokens_on_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_device_tokens_on_token ON public.device_tokens USING btree (token);


--
-- Name: index_device_tokens_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_device_tokens_on_user_id ON public.device_tokens USING btree (user_id);


--
-- Name: index_domains_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_domains_on_app_record_id ON public.domains USING btree (app_record_id);


--
-- Name: index_domains_on_hostname; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_domains_on_hostname ON public.domains USING btree (hostname);


--
-- Name: index_dyno_allocations_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dyno_allocations_on_app_record_id ON public.dyno_allocations USING btree (app_record_id);


--
-- Name: index_dyno_allocations_on_dyno_tier_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_dyno_allocations_on_dyno_tier_id ON public.dyno_allocations USING btree (dyno_tier_id);


--
-- Name: index_dyno_tiers_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_dyno_tiers_on_name ON public.dyno_tiers USING btree (name);


--
-- Name: index_env_vars_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_env_vars_on_app_record_id ON public.env_vars USING btree (app_record_id);


--
-- Name: index_env_vars_on_app_record_id_and_key_and_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_env_vars_on_app_record_id_and_key_and_scope ON public.env_vars USING btree (app_record_id, key, scope);


--
-- Name: index_env_vars_on_app_record_id_and_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_env_vars_on_app_record_id_and_scope ON public.env_vars USING btree (app_record_id, scope);


--
-- Name: index_feedback_entries_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_entries_on_created_at ON public.feedback_entries USING btree (created_at);


--
-- Name: index_feedback_entries_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_feedback_entries_on_user_id ON public.feedback_entries USING btree (user_id);


--
-- Name: index_incidents_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_incidents_on_app_record_id ON public.incidents USING btree (app_record_id);


--
-- Name: index_incidents_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_incidents_on_server_id ON public.incidents USING btree (server_id);


--
-- Name: index_incidents_open_per_app; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_incidents_open_per_app ON public.incidents USING btree (app_record_id) WHERE ((resolved_at IS NULL) AND (app_record_id IS NOT NULL));


--
-- Name: index_incidents_open_per_server; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_incidents_open_per_server ON public.incidents USING btree (server_id) WHERE ((resolved_at IS NULL) AND (server_id IS NOT NULL));


--
-- Name: index_invoices_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_plan_id ON public.invoices USING btree (plan_id);


--
-- Name: index_invoices_on_reference_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoices_on_reference_id ON public.invoices USING btree (reference_id);


--
-- Name: index_invoices_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_team_id ON public.invoices USING btree (team_id);


--
-- Name: index_invoices_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_user_id ON public.invoices USING btree (user_id);


--
-- Name: index_invoices_on_user_id_and_period_start; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_user_id_and_period_start ON public.invoices USING btree (user_id, period_start);


--
-- Name: index_known_devices_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_known_devices_on_user_id ON public.known_devices USING btree (user_id);


--
-- Name: index_leads_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_created_at ON public.leads USING btree (created_at);


--
-- Name: index_leads_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_leads_on_user_id ON public.leads USING btree (user_id);


--
-- Name: index_lifecycle_ops_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lifecycle_ops_on_app_record_id ON public.lifecycle_ops USING btree (app_record_id);


--
-- Name: index_lifecycle_ops_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lifecycle_ops_on_server_id ON public.lifecycle_ops USING btree (server_id);


--
-- Name: index_lifecycle_ops_one_live_per_app; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lifecycle_ops_one_live_per_app ON public.lifecycle_ops USING btree (app_record_id) WHERE (status = ANY (ARRAY[0, 1]));


--
-- Name: index_logs_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_logs_on_app_record_id ON public.logs USING btree (app_record_id);


--
-- Name: index_logs_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_logs_on_server_id ON public.logs USING btree (server_id);


--
-- Name: index_metric_hourly_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metric_hourly_on_app_record_id ON public.metric_hourly USING btree (app_record_id);


--
-- Name: index_metrics_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metrics_on_app_record_id ON public.metrics USING btree (app_record_id);


--
-- Name: index_mobile_auth_codes_on_code_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_mobile_auth_codes_on_code_digest ON public.mobile_auth_codes USING btree (code_digest);


--
-- Name: index_mobile_auth_codes_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_mobile_auth_codes_on_user_id ON public.mobile_auth_codes USING btree (user_id);


--
-- Name: index_notifications_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_app_record_id ON public.notifications USING btree (app_record_id);


--
-- Name: index_notifications_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_team_id ON public.notifications USING btree (team_id);


--
-- Name: index_object_storage_buckets_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_object_storage_buckets_on_app_record_id ON public.object_storage_buckets USING btree (app_record_id);


--
-- Name: index_object_storage_buckets_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_object_storage_buckets_on_name ON public.object_storage_buckets USING btree (name);


--
-- Name: index_object_storage_buckets_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_object_storage_buckets_on_team_id ON public.object_storage_buckets USING btree (team_id);


--
-- Name: index_oss_revenue_shares_on_template_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oss_revenue_shares_on_template_slug ON public.oss_revenue_shares USING btree (template_slug);


--
-- Name: index_plans_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_on_key ON public.plans USING btree (key);


--
-- Name: index_plans_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_on_name ON public.plans USING btree (name);


--
-- Name: index_plans_on_stripe_price_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_on_stripe_price_id ON public.plans USING btree (stripe_price_id);


--
-- Name: index_preview_dns_records_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_preview_dns_records_on_app_record_id ON public.preview_dns_records USING btree (app_record_id);


--
-- Name: index_preview_dns_records_on_hostname; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_preview_dns_records_on_hostname ON public.preview_dns_records USING btree (hostname);


--
-- Name: index_process_scales_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_process_scales_on_app_record_id ON public.process_scales USING btree (app_record_id);


--
-- Name: index_push_tickets_on_checked_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_tickets_on_checked_at ON public.push_tickets USING btree (checked_at);


--
-- Name: index_push_tickets_on_device_token_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_push_tickets_on_device_token_id ON public.push_tickets USING btree (device_token_id);


--
-- Name: index_push_tickets_on_ticket_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_push_tickets_on_ticket_id ON public.push_tickets USING btree (ticket_id);


--
-- Name: index_releases_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_releases_on_app_record_id ON public.releases USING btree (app_record_id);


--
-- Name: index_releases_on_deploy_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_releases_on_deploy_id ON public.releases USING btree (deploy_id);


--
-- Name: index_request_aggregates_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_request_aggregates_on_app_record_id ON public.request_aggregates USING btree (app_record_id);


--
-- Name: index_request_samples_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_request_samples_on_app_record_id ON public.request_samples USING btree (app_record_id);


--
-- Name: index_request_samples_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_request_samples_on_server_id ON public.request_samples USING btree (server_id);


--
-- Name: index_restore_drills_on_backup_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_restore_drills_on_backup_id ON public.restore_drills USING btree (backup_id);


--
-- Name: index_restore_drills_on_database_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_restore_drills_on_database_service_id ON public.restore_drills USING btree (database_service_id);


--
-- Name: index_scheduled_task_runs_on_scheduled_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scheduled_task_runs_on_scheduled_task_id ON public.scheduled_task_runs USING btree (scheduled_task_id);


--
-- Name: index_scheduled_task_runs_on_scheduled_task_id_and_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_scheduled_task_runs_on_scheduled_task_id_and_started_at ON public.scheduled_task_runs USING btree (scheduled_task_id, started_at);


--
-- Name: index_scheduled_tasks_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scheduled_tasks_on_app_record_id ON public.scheduled_tasks USING btree (app_record_id);


--
-- Name: index_scheduled_tasks_on_app_record_id_and_schedule; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_scheduled_tasks_on_app_record_id_and_schedule ON public.scheduled_tasks USING btree (app_record_id, schedule);


--
-- Name: index_servers_on_heartbeat_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_servers_on_heartbeat_status ON public.servers USING btree (heartbeat_status);


--
-- Name: index_servers_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_servers_on_team_id ON public.servers USING btree (team_id);


--
-- Name: index_service_ops_on_database_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_ops_on_database_service_id ON public.service_ops USING btree (database_service_id);


--
-- Name: index_service_ops_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_ops_on_server_id ON public.service_ops USING btree (server_id);


--
-- Name: index_service_ops_on_server_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_service_ops_on_server_id_and_status ON public.service_ops USING btree (server_id, status);


--
-- Name: index_service_tiers_on_service_type_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_service_tiers_on_service_type_and_name ON public.service_tiers USING btree (service_type, name);


--
-- Name: index_solid_queue_blocked_executions_for_maintenance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_maintenance ON public.solid_queue_blocked_executions USING btree (expires_at, concurrency_key);


--
-- Name: index_solid_queue_blocked_executions_for_release; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_blocked_executions_for_release ON public.solid_queue_blocked_executions USING btree (concurrency_key, priority, job_id);


--
-- Name: index_solid_queue_blocked_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_blocked_executions_on_job_id ON public.solid_queue_blocked_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_claimed_executions_on_job_id ON public.solid_queue_claimed_executions USING btree (job_id);


--
-- Name: index_solid_queue_claimed_executions_on_process_id_and_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_claimed_executions_on_process_id_and_job_id ON public.solid_queue_claimed_executions USING btree (process_id, job_id);


--
-- Name: index_solid_queue_dispatch_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_dispatch_all ON public.solid_queue_scheduled_executions USING btree (scheduled_at, priority, job_id);


--
-- Name: index_solid_queue_failed_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_failed_executions_on_job_id ON public.solid_queue_failed_executions USING btree (job_id);


--
-- Name: index_solid_queue_jobs_for_alerting; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_alerting ON public.solid_queue_jobs USING btree (scheduled_at, finished_at);


--
-- Name: index_solid_queue_jobs_for_filtering; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_for_filtering ON public.solid_queue_jobs USING btree (queue_name, finished_at);


--
-- Name: index_solid_queue_jobs_on_active_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_active_job_id ON public.solid_queue_jobs USING btree (active_job_id);


--
-- Name: index_solid_queue_jobs_on_class_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_class_name ON public.solid_queue_jobs USING btree (class_name);


--
-- Name: index_solid_queue_jobs_on_finished_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_jobs_on_finished_at ON public.solid_queue_jobs USING btree (finished_at);


--
-- Name: index_solid_queue_pauses_on_queue_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_pauses_on_queue_name ON public.solid_queue_pauses USING btree (queue_name);


--
-- Name: index_solid_queue_poll_all; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_all ON public.solid_queue_ready_executions USING btree (priority, job_id);


--
-- Name: index_solid_queue_poll_by_queue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_poll_by_queue ON public.solid_queue_ready_executions USING btree (queue_name, priority, job_id);


--
-- Name: index_solid_queue_processes_on_last_heartbeat_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_last_heartbeat_at ON public.solid_queue_processes USING btree (last_heartbeat_at);


--
-- Name: index_solid_queue_processes_on_name_and_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_processes_on_name_and_supervisor_id ON public.solid_queue_processes USING btree (name, supervisor_id);


--
-- Name: index_solid_queue_processes_on_supervisor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_processes_on_supervisor_id ON public.solid_queue_processes USING btree (supervisor_id);


--
-- Name: index_solid_queue_ready_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_ready_executions_on_job_id ON public.solid_queue_ready_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_job_id ON public.solid_queue_recurring_executions USING btree (job_id);


--
-- Name: index_solid_queue_recurring_executions_on_task_key_and_run_at; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_executions_on_task_key_and_run_at ON public.solid_queue_recurring_executions USING btree (task_key, run_at);


--
-- Name: index_solid_queue_recurring_tasks_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_recurring_tasks_on_key ON public.solid_queue_recurring_tasks USING btree (key);


--
-- Name: index_solid_queue_recurring_tasks_on_static; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_recurring_tasks_on_static ON public.solid_queue_recurring_tasks USING btree (static);


--
-- Name: index_solid_queue_scheduled_executions_on_job_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_scheduled_executions_on_job_id ON public.solid_queue_scheduled_executions USING btree (job_id);


--
-- Name: index_solid_queue_semaphores_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_expires_at ON public.solid_queue_semaphores USING btree (expires_at);


--
-- Name: index_solid_queue_semaphores_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_solid_queue_semaphores_on_key ON public.solid_queue_semaphores USING btree (key);


--
-- Name: index_solid_queue_semaphores_on_key_and_value; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_solid_queue_semaphores_on_key_and_value ON public.solid_queue_semaphores USING btree (key, value);


--
-- Name: index_ssh_public_keys_on_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ssh_public_keys_on_fingerprint ON public.ssh_public_keys USING btree (fingerprint);


--
-- Name: index_ssh_public_keys_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ssh_public_keys_on_user_id ON public.ssh_public_keys USING btree (user_id);


--
-- Name: index_storage_backup_runs_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_storage_backup_runs_on_server_id ON public.storage_backup_runs USING btree (server_id);


--
-- Name: index_storage_backup_runs_on_server_id_and_kind_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_storage_backup_runs_on_server_id_and_kind_and_created_at ON public.storage_backup_runs USING btree (server_id, kind, created_at);


--
-- Name: index_subscriptions_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_plan_id ON public.subscriptions USING btree (plan_id);


--
-- Name: index_subscriptions_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_team_id ON public.subscriptions USING btree (team_id);


--
-- Name: index_subscriptions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_user_id ON public.subscriptions USING btree (user_id);


--
-- Name: index_team_memberships_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_team_id ON public.team_memberships USING btree (team_id);


--
-- Name: index_team_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_user_id ON public.team_memberships USING btree (user_id);


--
-- Name: index_teams_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_name ON public.teams USING btree (name);


--
-- Name: index_teams_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teams_on_owner_id ON public.teams USING btree (owner_id);


--
-- Name: index_teams_on_owner_id_personal; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_owner_id_personal ON public.teams USING btree (owner_id) WHERE (kind = 0);


--
-- Name: index_teams_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teams_on_plan_id ON public.teams USING btree (plan_id);


--
-- Name: index_teams_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_slug ON public.teams USING btree (slug);


--
-- Name: index_tunnel_sessions_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tunnel_sessions_on_app_record_id ON public.tunnel_sessions USING btree (app_record_id);


--
-- Name: index_tunnel_sessions_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tunnel_sessions_on_server_id ON public.tunnel_sessions USING btree (server_id);


--
-- Name: index_tunnel_sessions_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tunnel_sessions_on_token_digest ON public.tunnel_sessions USING btree (token_digest);


--
-- Name: index_tunnel_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tunnel_sessions_on_user_id ON public.tunnel_sessions USING btree (user_id);


--
-- Name: index_usage_events_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_usage_events_on_app_record_id ON public.usage_events USING btree (app_record_id);


--
-- Name: index_usage_events_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_usage_events_on_user_id ON public.usage_events USING btree (user_id);


--
-- Name: index_users_on_apple_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_apple_uid ON public.users USING btree (apple_uid);


--
-- Name: index_users_on_deleted_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_deleted_at ON public.users USING btree (deleted_at);


--
-- Name: index_users_on_deletion_scheduled_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_deletion_scheduled_at ON public.users USING btree (deletion_scheduled_at);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_github_installation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_github_installation_id ON public.users USING btree (github_installation_id);


--
-- Name: index_users_on_otp_secret; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_otp_secret ON public.users USING btree (otp_secret);


--
-- Name: index_users_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_plan_id ON public.users USING btree (plan_id);


--
-- Name: index_users_on_provider_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_provider_and_uid ON public.users USING btree (provider, uid);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: index_users_on_unlock_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_unlock_token ON public.users USING btree (unlock_token);


--
-- Name: index_users_single_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_single_admin ON public.users USING btree (role) WHERE (role = 1);


--
-- Name: index_vitals_events_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vitals_events_on_app_record_id ON public.vitals_events USING btree (app_record_id);


--
-- Name: index_vitals_hourly_rollups_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_vitals_hourly_rollups_on_app_record_id ON public.vitals_hourly_rollups USING btree (app_record_id);


--
-- Name: index_wildcard_certificates_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_wildcard_certificates_on_expires_at ON public.wildcard_certificates USING btree (expires_at);


--
-- Name: activities activities_no_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER activities_no_delete BEFORE DELETE ON public.activities FOR EACH ROW EXECUTE FUNCTION public.wokku_block_activity_mutation();


--
-- Name: activities activities_no_truncate; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER activities_no_truncate BEFORE TRUNCATE ON public.activities FOR EACH STATEMENT EXECUTE FUNCTION public.wokku_block_activity_mutation();


--
-- Name: activities activities_no_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER activities_no_update BEFORE UPDATE ON public.activities FOR EACH ROW EXECUTE FUNCTION public.wokku_block_activity_mutation();


--
-- Name: app_transfers fk_rails_09e4f6d1c3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_transfers
    ADD CONSTRAINT fk_rails_09e4f6d1c3 FOREIGN KEY (from_user_id) REFERENCES public.users(id);


--
-- Name: vitals_hourly_rollups fk_rails_0bb0430151; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vitals_hourly_rollups
    ADD CONSTRAINT fk_rails_0bb0430151 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: cloud_credentials fk_rails_0d62644389; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cloud_credentials
    ADD CONSTRAINT fk_rails_0d62644389 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: service_ops fk_rails_11f074f58d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_ops
    ADD CONSTRAINT fk_rails_11f074f58d FOREIGN KEY (database_service_id) REFERENCES public.database_services(id) ON DELETE CASCADE;


--
-- Name: dyno_allocations fk_rails_12cfa69864; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dyno_allocations
    ADD CONSTRAINT fk_rails_12cfa69864 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: certificates fk_rails_13b0a6586c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT fk_rails_13b0a6586c FOREIGN KEY (domain_id) REFERENCES public.domains(id);


--
-- Name: scheduled_task_runs fk_rails_14edbae655; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_task_runs
    ADD CONSTRAINT fk_rails_14edbae655 FOREIGN KEY (scheduled_task_id) REFERENCES public.scheduled_tasks(id);


--
-- Name: app_records fk_rails_1622217f59; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_records
    ADD CONSTRAINT fk_rails_1622217f59 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: app_databases fk_rails_16335c63ca; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_databases
    ADD CONSTRAINT fk_rails_16335c63ca FOREIGN KEY (database_service_id) REFERENCES public.database_services(id);


--
-- Name: box_addons fk_rails_17c1caa354; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.box_addons
    ADD CONSTRAINT fk_rails_17c1caa354 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: feedback_entries fk_rails_185d259fad; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback_entries
    ADD CONSTRAINT fk_rails_185d259fad FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: logs fk_rails_18f7c307b9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT fk_rails_18f7c307b9 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: leads fk_rails_1d08b36969; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leads
    ADD CONSTRAINT fk_rails_1d08b36969 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: service_ops fk_rails_1da4f77a46; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.service_ops
    ADD CONSTRAINT fk_rails_1da4f77a46 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: tunnel_sessions fk_rails_1dd385d86d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tunnel_sessions
    ADD CONSTRAINT fk_rails_1dd385d86d FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: app_transfers fk_rails_207c5c7c21; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_transfers
    ADD CONSTRAINT fk_rails_207c5c7c21 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: usage_events fk_rails_25a204774b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_events
    ADD CONSTRAINT fk_rails_25a204774b FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: deploys fk_rails_294c687f02; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deploys
    ADD CONSTRAINT fk_rails_294c687f02 FOREIGN KEY (release_id) REFERENCES public.releases(id) ON DELETE SET NULL;


--
-- Name: vitals_events fk_rails_294fb535fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vitals_events
    ADD CONSTRAINT fk_rails_294fb535fa FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: push_tickets fk_rails_2c26bf7873; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tickets
    ADD CONSTRAINT fk_rails_2c26bf7873 FOREIGN KEY (device_token_id) REFERENCES public.device_tokens(id);


--
-- Name: restore_drills fk_rails_2e1cf4ee67; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restore_drills
    ADD CONSTRAINT fk_rails_2e1cf4ee67 FOREIGN KEY (backup_id) REFERENCES public.backups(id) ON DELETE SET NULL;


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: dev_sessions fk_rails_32f8947070; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dev_sessions
    ADD CONSTRAINT fk_rails_32f8947070 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: backups fk_rails_3502e00075; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.backups
    ADD CONSTRAINT fk_rails_3502e00075 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id) ON DELETE SET NULL;


--
-- Name: invoices fk_rails_3784a47887; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_3784a47887 FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: notifications fk_rails_37d057eb4d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_37d057eb4d FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: object_storage_buckets fk_rails_38c9ec588b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.object_storage_buckets
    ADD CONSTRAINT fk_rails_38c9ec588b FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: crash_events fk_rails_3a602ea9fd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.crash_events
    ADD CONSTRAINT fk_rails_3a602ea9fd FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: invoices fk_rails_3d1522a0d8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_3d1522a0d8 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: app_records fk_rails_3e698f373d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_records
    ADD CONSTRAINT fk_rails_3e698f373d FOREIGN KEY (parent_app_id) REFERENCES public.app_records(id);


--
-- Name: object_storage_buckets fk_rails_4a8ed097ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.object_storage_buckets
    ADD CONSTRAINT fk_rails_4a8ed097ce FOREIGN KEY (app_record_id) REFERENCES public.app_records(id) ON DELETE SET NULL;


--
-- Name: tunnel_sessions fk_rails_4b370abce7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tunnel_sessions
    ADD CONSTRAINT fk_rails_4b370abce7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: solid_queue_blocked_executions fk_rails_4cd34e2228; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_blocked_executions
    ADD CONSTRAINT fk_rails_4cd34e2228 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: ssh_public_keys fk_rails_4cd52bba61; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ssh_public_keys
    ADD CONSTRAINT fk_rails_4cd52bba61 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: known_devices fk_rails_55d8940c29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.known_devices
    ADD CONSTRAINT fk_rails_55d8940c29 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: incidents fk_rails_5633f69671; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT fk_rails_5633f69671 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: device_authorizations fk_rails_576e920022; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_authorizations
    ADD CONSTRAINT fk_rails_576e920022 FOREIGN KEY (api_token_id) REFERENCES public.api_tokens(id);


--
-- Name: env_vars fk_rails_59639ba9da; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.env_vars
    ADD CONSTRAINT fk_rails_59639ba9da FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: team_memberships fk_rails_5aba9331a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_5aba9331a7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: backups fk_rails_5dd9cfa870; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.backups
    ADD CONSTRAINT fk_rails_5dd9cfa870 FOREIGN KEY (backup_destination_id) REFERENCES public.backup_destinations(id);


--
-- Name: incidents fk_rails_5fd92da493; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.incidents
    ADD CONSTRAINT fk_rails_5fd92da493 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: team_memberships fk_rails_61c29b529e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_61c29b529e FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: database_services fk_rails_62ae976398; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_services
    ADD CONSTRAINT fk_rails_62ae976398 FOREIGN KEY (creator_id) REFERENCES public.users(id);


--
-- Name: subscriptions fk_rails_63d3df128b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_63d3df128b FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: lifecycle_ops fk_rails_6bc4fc2b26; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lifecycle_ops
    ADD CONSTRAINT fk_rails_6bc4fc2b26 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: alert_mutes fk_rails_6e706cd2c8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_mutes
    ADD CONSTRAINT fk_rails_6e706cd2c8 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: dev_sessions fk_rails_75f65a0854; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dev_sessions
    ADD CONSTRAINT fk_rails_75f65a0854 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: metrics fk_rails_792cf6e72c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT fk_rails_792cf6e72c FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: database_services fk_rails_7b79c0ba51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_services
    ADD CONSTRAINT fk_rails_7b79c0ba51 FOREIGN KEY (parent_service_id) REFERENCES public.database_services(id);


--
-- Name: activities fk_rails_7e11bb717f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_7e11bb717f FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: invoices fk_rails_807e09985d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invoices
    ADD CONSTRAINT fk_rails_807e09985d FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: device_tokens fk_rails_86292fb988; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT fk_rails_86292fb988 FOREIGN KEY (api_token_id) REFERENCES public.api_tokens(id);


--
-- Name: process_scales fk_rails_8bdcd5b0da; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.process_scales
    ADD CONSTRAINT fk_rails_8bdcd5b0da FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: releases fk_rails_8c917dd85d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT fk_rails_8c917dd85d FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: device_authorizations fk_rails_8f880d595f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_authorizations
    ADD CONSTRAINT fk_rails_8f880d595f FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: backups fk_rails_923e9f81c1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.backups
    ADD CONSTRAINT fk_rails_923e9f81c1 FOREIGN KEY (database_service_id) REFERENCES public.database_services(id);


--
-- Name: subscriptions fk_rails_933bdff476; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_933bdff476 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: app_records fk_rails_97502e517b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_records
    ADD CONSTRAINT fk_rails_97502e517b FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: restore_drills fk_rails_9a7220825a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restore_drills
    ADD CONSTRAINT fk_rails_9a7220825a FOREIGN KEY (database_service_id) REFERENCES public.database_services(id) ON DELETE SET NULL;


--
-- Name: subscriptions fk_rails_9c6c113221; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_9c6c113221 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: solid_queue_claimed_executions fk_rails_9cfe4d4944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_claimed_executions
    ADD CONSTRAINT fk_rails_9cfe4d4944 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: servers fk_rails_a376138104; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.servers
    ADD CONSTRAINT fk_rails_a376138104 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: preview_dns_records fk_rails_a39c2fe5ec; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preview_dns_records
    ADD CONSTRAINT fk_rails_a39c2fe5ec FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: releases fk_rails_a4634a56aa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.releases
    ADD CONSTRAINT fk_rails_a4634a56aa FOREIGN KEY (deploy_id) REFERENCES public.deploys(id);


--
-- Name: backup_destinations fk_rails_ad2b2f8955; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.backup_destinations
    ADD CONSTRAINT fk_rails_ad2b2f8955 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: scheduled_tasks fk_rails_af964cd264; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.scheduled_tasks
    ADD CONSTRAINT fk_rails_af964cd264 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: alert_mutes fk_rails_b2df00d648; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alert_mutes
    ADD CONSTRAINT fk_rails_b2df00d648 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id) ON DELETE CASCADE;


--
-- Name: request_samples fk_rails_bbc071f07a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_samples
    ADD CONSTRAINT fk_rails_bbc071f07a FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: box_addons fk_rails_bca6478ecd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.box_addons
    ADD CONSTRAINT fk_rails_bca6478ecd FOREIGN KEY (invoice_id) REFERENCES public.invoices(id);


--
-- Name: lifecycle_ops fk_rails_c00a8d27dd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lifecycle_ops
    ADD CONSTRAINT fk_rails_c00a8d27dd FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: mobile_auth_codes fk_rails_c34d3e8dcc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mobile_auth_codes
    ADD CONSTRAINT fk_rails_c34d3e8dcc FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: tunnel_sessions fk_rails_c4645b9cd3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tunnel_sessions
    ADD CONSTRAINT fk_rails_c4645b9cd3 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: users fk_rails_c7d01481e8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_c7d01481e8 FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: database_services fk_rails_d34d450af6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_services
    ADD CONSTRAINT fk_rails_d34d450af6 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: storage_backup_runs fk_rails_d36111b548; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.storage_backup_runs
    ADD CONSTRAINT fk_rails_d36111b548 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: activities fk_rails_d67d554927; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_d67d554927 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: logs fk_rails_d782a21ec2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logs
    ADD CONSTRAINT fk_rails_d782a21ec2 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: notifications fk_rails_d7f8ec73b1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_d7f8ec73b1 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: deploys fk_rails_dbf8af1084; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deploys
    ADD CONSTRAINT fk_rails_dbf8af1084 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: app_databases fk_rails_e067c7bef4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_databases
    ADD CONSTRAINT fk_rails_e067c7bef4 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: app_records fk_rails_e2b0279140; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_records
    ADD CONSTRAINT fk_rails_e2b0279140 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: request_samples fk_rails_e32645cc06; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_samples
    ADD CONSTRAINT fk_rails_e32645cc06 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: teams fk_rails_e62f95aa33; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_e62f95aa33 FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: device_tokens fk_rails_e99e290457; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.device_tokens
    ADD CONSTRAINT fk_rails_e99e290457 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: metric_hourly fk_rails_ebf9ba3e7a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metric_hourly
    ADD CONSTRAINT fk_rails_ebf9ba3e7a FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: usage_events fk_rails_f0cde5a00d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_events
    ADD CONSTRAINT fk_rails_f0cde5a00d FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: domains fk_rails_f159c0f8a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domains
    ADD CONSTRAINT fk_rails_f159c0f8a0 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: api_tokens fk_rails_f16b5e0447; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_tokens
    ADD CONSTRAINT fk_rails_f16b5e0447 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: request_aggregates fk_rails_f77dffa89c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_aggregates
    ADD CONSTRAINT fk_rails_f77dffa89c FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


--
-- Name: database_stats_snapshots fk_rails_fa34cb695a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_stats_snapshots
    ADD CONSTRAINT fk_rails_fa34cb695a FOREIGN KEY (database_service_id) REFERENCES public.database_services(id) ON DELETE CASCADE;


--
-- Name: app_transfers fk_rails_fa46e01b1c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_transfers
    ADD CONSTRAINT fk_rails_fa46e01b1c FOREIGN KEY (to_user_id) REFERENCES public.users(id);


--
-- Name: teams fk_rails_fe85bf605a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_fe85bf605a FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: dyno_allocations fk_rails_fee2ab37e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dyno_allocations
    ADD CONSTRAINT fk_rails_fee2ab37e5 FOREIGN KEY (dyno_tier_id) REFERENCES public.dyno_tiers(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261120000002'),
('20261120000001'),
('20261119120001'),
('20261118000001'),
('20261117000001'),
('20261116000001'),
('20261115000003'),
('20261115000002'),
('20261115000001'),
('20261031000001'),
('20261025200001'),
('20261025100001'),
('20261025000001'),
('20261024000001'),
('20261023000002'),
('20261023000001'),
('20261019000001'),
('20260925000001'),
('20260806050000'),
('20260801000000'),
('20260729042535'),
('20260729000002'),
('20260729000001'),
('20260728141037'),
('20260727003805'),
('20260724104937'),
('20260722085539'),
('20260720113708'),
('20260719032006'),
('20260716000001'),
('20260715000002'),
('20260715000001'),
('20260714000002'),
('20260714000001'),
('20260711000004'),
('20260711000003'),
('20260711000002'),
('20260711000001'),
('20260710000002'),
('20260710000001'),
('20260708000001'),
('20260706000001'),
('20260704090019'),
('20260703222106'),
('20260627120000'),
('20260619090000'),
('20260616120100'),
('20260616120000'),
('20260616090000'),
('20260609164939'),
('20260609144715'),
('20260609130519'),
('20260609125724'),
('20260604013958'),
('20260603140954'),
('20260602144824'),
('20260601163412'),
('20260601163411'),
('20260601163406'),
('20260601113630'),
('20260530182311'),
('20260530121610'),
('20260529300001'),
('20260529200001'),
('20260529100001'),
('20260528100001'),
('20260528000002'),
('20260528000001'),
('20260527100004'),
('20260527100003'),
('20260527100002'),
('20260527100001'),
('20260527000030'),
('20260527000020'),
('20260527000011'),
('20260527000010'),
('20260527000002'),
('20260527000001'),
('20260526000001'),
('20260525000002'),
('20260525000001'),
('20260524000010'),
('20260524000001'),
('20260522161334'),
('20260522161309'),
('20260522074222'),
('20260522024424'),
('20260521125518'),
('20260521070001'),
('20260521070000'),
('20260521060528'),
('20260521060351'),
('20260521060333'),
('20260520030000'),
('20260519030000'),
('20260518030000'),
('20260516020000'),
('20260513015042'),
('20260510025835'),
('20260509162743'),
('20260508090000'),
('20260508085228'),
('20260506235156'),
('20260506232540'),
('20260506160000'),
('20260506085536'),
('20260502210200'),
('20260430151708'),
('20260430145538'),
('20260430120000'),
('20260430090000'),
('20260429110000'),
('20260429100000'),
('20260428230000'),
('20260428220000'),
('20260428210000'),
('20260428200000'),
('20260428100000'),
('20260427200000'),
('20260427124717'),
('20260426040000'),
('20260426030000'),
('20260426020000'),
('20260426010000'),
('20260426000000'),
('20260425220000'),
('20260425200004'),
('20260425200003'),
('20260425200002'),
('20260425200001'),
('20260425200000'),
('20260425100000'),
('20260424120001'),
('20260424120000'),
('20260424110000'),
('20260424100000'),
('20260422210000'),
('20260422180000'),
('20260421203419'),
('20260421203418'),
('20260421201407'),
('20260421195540'),
('20260418130341'),
('20260415203212'),
('20260415195904'),
('20260411000001'),
('20260404060506'),
('20260404060426'),
('20260404060414'),
('20260403175436'),
('20260402150429'),
('20260402085232'),
('20260402022539'),
('20260401093413'),
('20260331065340'),
('20260331023938'),
('20260330000001'),
('20260325000005'),
('20260325000004'),
('20260325000003'),
('20260325000002'),
('20260325000001'),
('20260324000003'),
('20260324000002'),
('20260324000001'),
('20260322000005'),
('20260322000004'),
('20260322000003'),
('20260322000002'),
('20260322000001'),
('20260314034149'),
('20260314000007'),
('20260314000006'),
('20260314000005'),
('20260314000004'),
('20260314000003'),
('20260314000002'),
('20260314000001'),
('20260313083315'),
('20260313083310'),
('20260313074610'),
('20260313060640'),
('20260313060639'),
('20260313060638'),
('20260313060637'),
('20260313060636'),
('20260313060635'),
('20260313060634'),
('20260313060632'),
('20260313060631'),
('20260313060417'),
('20260313060218'),
('20260313060059'),
('20260313060055'),
('20260313055614'),
('20260313055244'),
('20260313055053');

