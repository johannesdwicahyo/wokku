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
    user_id uuid NOT NULL
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
    live_metrics_at timestamp(6) without time zone
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
    database_service_id uuid NOT NULL
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
    live_metrics_at timestamp(6) without time zone
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
    release_id uuid
);


--
-- Name: deposit_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposit_transactions (
    amount integer NOT NULL,
    currency character varying NOT NULL,
    payment_gateway character varying NOT NULL,
    gateway_ref character varying,
    status character varying DEFAULT 'pending'::character varying,
    notes text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL
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
    user_id uuid NOT NULL
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
    app_record_id uuid NOT NULL
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
    dyno_tier_id uuid NOT NULL
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
    app_record_id uuid NOT NULL
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
    user_id uuid NOT NULL
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
-- Name: log_drains; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.log_drains (
    url character varying,
    drain_type character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    app_record_id uuid NOT NULL
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
    max_apps integer NOT NULL,
    max_dynos integer,
    max_databases integer,
    price_cents_per_month integer,
    stripe_price_id character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL
);


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
-- Name: resource_usages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.resource_usages (
    resource_type character varying NOT NULL,
    resource_id_ref character varying NOT NULL,
    tier_name character varying NOT NULL,
    price_cents_per_hour numeric(10,4) DEFAULT 0.0 NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    stopped_at timestamp(6) without time zone,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    id uuid DEFAULT public.uuidv7() NOT NULL,
    user_id uuid NOT NULL
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
    capacity_used_mb integer DEFAULT 0,
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
    live_metrics_at timestamp(6) without time zone
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
    user_id uuid NOT NULL
);


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
    owner_id uuid NOT NULL
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
    balance_idr integer DEFAULT 0 NOT NULL,
    balance_usd_cents integer DEFAULT 0 NOT NULL,
    payment_method_type character varying DEFAULT 'none'::character varying,
    id uuid DEFAULT public.uuidv7() NOT NULL
);


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
-- Name: database_services database_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_services
    ADD CONSTRAINT database_services_pkey PRIMARY KEY (id);


--
-- Name: deploys deploys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deploys
    ADD CONSTRAINT deploys_pkey PRIMARY KEY (id);


--
-- Name: deposit_transactions deposit_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_transactions
    ADD CONSTRAINT deposit_transactions_pkey PRIMARY KEY (id);


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
-- Name: log_drains log_drains_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_drains
    ADD CONSTRAINT log_drains_pkey PRIMARY KEY (id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


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
-- Name: resource_usages resource_usages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_usages
    ADD CONSTRAINT resource_usages_pkey PRIMARY KEY (id);


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
-- Name: index_app_records_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_created_by_id ON public.app_records USING btree (created_by_id);


--
-- Name: index_app_records_on_github_repo_full_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_github_repo_full_name ON public.app_records USING btree (github_repo_full_name);


--
-- Name: index_app_records_on_parent_app_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_parent_app_id ON public.app_records USING btree (parent_app_id);


--
-- Name: index_app_records_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_server_id ON public.app_records USING btree (server_id);


--
-- Name: index_app_records_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_app_records_on_team_id ON public.app_records USING btree (team_id);


--
-- Name: index_backup_destinations_on_server_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_backup_destinations_on_server_id ON public.backup_destinations USING btree (server_id);


--
-- Name: index_backups_on_backup_destination_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_backups_on_backup_destination_id ON public.backups USING btree (backup_destination_id);


--
-- Name: index_backups_on_database_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_backups_on_database_service_id ON public.backups USING btree (database_service_id);


--
-- Name: index_certificates_on_domain_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_certificates_on_domain_id ON public.certificates USING btree (domain_id);


--
-- Name: index_cloud_credentials_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cloud_credentials_on_team_id ON public.cloud_credentials USING btree (team_id);


--
-- Name: index_database_services_on_parent_service_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_database_services_on_parent_service_id ON public.database_services USING btree (parent_service_id);


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
-- Name: index_deploys_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deploys_on_app_record_id ON public.deploys USING btree (app_record_id);


--
-- Name: index_deploys_on_release_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deploys_on_release_id ON public.deploys USING btree (release_id);


--
-- Name: index_deposit_transactions_on_gateway_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_transactions_on_gateway_ref ON public.deposit_transactions USING btree (gateway_ref);


--
-- Name: index_deposit_transactions_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_transactions_on_status ON public.deposit_transactions USING btree (status);


--
-- Name: index_deposit_transactions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_deposit_transactions_on_user_id ON public.deposit_transactions USING btree (user_id);


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
-- Name: index_invoices_on_reference_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invoices_on_reference_id ON public.invoices USING btree (reference_id);


--
-- Name: index_invoices_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invoices_on_user_id ON public.invoices USING btree (user_id);


--
-- Name: index_known_devices_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_known_devices_on_user_id ON public.known_devices USING btree (user_id);


--
-- Name: index_log_drains_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_log_drains_on_app_record_id ON public.log_drains USING btree (app_record_id);


--
-- Name: index_metrics_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_metrics_on_app_record_id ON public.metrics USING btree (app_record_id);


--
-- Name: index_notifications_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_app_record_id ON public.notifications USING btree (app_record_id);


--
-- Name: index_notifications_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notifications_on_team_id ON public.notifications USING btree (team_id);


--
-- Name: index_oss_revenue_shares_on_template_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_oss_revenue_shares_on_template_slug ON public.oss_revenue_shares USING btree (template_slug);


--
-- Name: index_plans_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_on_name ON public.plans USING btree (name);


--
-- Name: index_plans_on_stripe_price_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_plans_on_stripe_price_id ON public.plans USING btree (stripe_price_id);


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
-- Name: index_resource_usages_on_resource_type_and_resource_id_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_resource_usages_on_resource_type_and_resource_id_ref ON public.resource_usages USING btree (resource_type, resource_id_ref);


--
-- Name: index_resource_usages_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_resource_usages_on_user_id ON public.resource_usages USING btree (user_id);


--
-- Name: index_servers_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_servers_on_team_id ON public.servers USING btree (team_id);


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
-- Name: index_subscriptions_on_plan_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subscriptions_on_plan_id ON public.subscriptions USING btree (plan_id);


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
-- Name: index_usage_events_on_app_record_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_usage_events_on_app_record_id ON public.usage_events USING btree (app_record_id);


--
-- Name: index_usage_events_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_usage_events_on_user_id ON public.usage_events USING btree (user_id);


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
-- Name: cloud_credentials fk_rails_0d62644389; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cloud_credentials
    ADD CONSTRAINT fk_rails_0d62644389 FOREIGN KEY (team_id) REFERENCES public.teams(id);


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
-- Name: push_tickets fk_rails_2c26bf7873; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.push_tickets
    ADD CONSTRAINT fk_rails_2c26bf7873 FOREIGN KEY (device_token_id) REFERENCES public.device_tokens(id);


--
-- Name: resource_usages fk_rails_3157a74e5e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.resource_usages
    ADD CONSTRAINT fk_rails_3157a74e5e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: solid_queue_recurring_executions fk_rails_318a5533ed; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_recurring_executions
    ADD CONSTRAINT fk_rails_318a5533ed FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: notifications fk_rails_37d057eb4d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT fk_rails_37d057eb4d FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: solid_queue_failed_executions fk_rails_39bbc7a631; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_failed_executions
    ADD CONSTRAINT fk_rails_39bbc7a631 FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


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
-- Name: team_memberships fk_rails_61c29b529e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_61c29b529e FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: subscriptions fk_rails_63d3df128b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT fk_rails_63d3df128b FOREIGN KEY (plan_id) REFERENCES public.plans(id);


--
-- Name: deposit_transactions fk_rails_70554f2c12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposit_transactions
    ADD CONSTRAINT fk_rails_70554f2c12 FOREIGN KEY (user_id) REFERENCES public.users(id);


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
-- Name: solid_queue_ready_executions fk_rails_81fcbd66af; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_ready_executions
    ADD CONSTRAINT fk_rails_81fcbd66af FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


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
-- Name: solid_queue_scheduled_executions fk_rails_c4316f352d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.solid_queue_scheduled_executions
    ADD CONSTRAINT fk_rails_c4316f352d FOREIGN KEY (job_id) REFERENCES public.solid_queue_jobs(id) ON DELETE CASCADE;


--
-- Name: database_services fk_rails_d34d450af6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.database_services
    ADD CONSTRAINT fk_rails_d34d450af6 FOREIGN KEY (server_id) REFERENCES public.servers(id);


--
-- Name: activities fk_rails_d67d554927; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activities
    ADD CONSTRAINT fk_rails_d67d554927 FOREIGN KEY (team_id) REFERENCES public.teams(id);


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
-- Name: log_drains fk_rails_fe69ac4a13; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.log_drains
    ADD CONSTRAINT fk_rails_fe69ac4a13 FOREIGN KEY (app_record_id) REFERENCES public.app_records(id);


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

