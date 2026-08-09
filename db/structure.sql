SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

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
-- Name: audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid,
    actor_id uuid NOT NULL,
    event_type text NOT NULL,
    subject_id uuid,
    case_id uuid,
    investigation_id uuid,
    staff_member_id uuid,
    occurred_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: case_correlation_scopes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.case_correlation_scopes (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    domain_key text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: case_dispositions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.case_dispositions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    case_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    code text NOT NULL,
    notes text,
    action_type text,
    external_reference text,
    disposed_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT case_dispositions_code_check CHECK ((code = ANY (ARRAY['action_taken'::text, 'expected_change'::text, 'instrumentation_issue'::text, 'data_quality_issue'::text, 'already_known'::text, 'not_actionable'::text, 'insufficient_evidence'::text, 'duplicate'::text, 'false_positive'::text, 'escalated_external'::text])))
);


--
-- Name: case_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.case_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    case_id uuid NOT NULL,
    event_type text NOT NULL,
    actor_type text DEFAULT 'system'::text NOT NULL,
    actor_id uuid,
    occurred_at timestamp(6) without time zone NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    prev_hash text,
    row_hash text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: case_signals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.case_signals (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    case_id uuid NOT NULL,
    signal_id uuid NOT NULL,
    relationship text DEFAULT 'trigger'::text NOT NULL,
    attached_at timestamp(6) without time zone NOT NULL,
    explanation jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT case_signals_relationship_check CHECK ((relationship = ANY (ARRAY['trigger'::text, 'supporting'::text, 'contextual'::text, 'reopening'::text])))
);


--
-- Name: cases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cases (
    id uuid DEFAULT uuidv7() NOT NULL,
    public_id text NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    domain_key text NOT NULL,
    case_type text NOT NULL,
    title text,
    summary text,
    status text DEFAULT 'new'::text NOT NULL,
    review_priority text DEFAULT 'routine'::text NOT NULL,
    priority_reasons jsonb DEFAULT '[]'::jsonb NOT NULL,
    owner_id uuid,
    team_id uuid,
    started_at timestamp(6) without time zone NOT NULL,
    detected_at timestamp(6) without time zone NOT NULL,
    last_signal_at timestamp(6) without time zone,
    evidence_level text,
    data_quality_state text,
    baseline_maturity text,
    analysis_status text DEFAULT 'not_started'::text NOT NULL,
    analysis_as_of timestamp(6) without time zone,
    current_context_id uuid,
    current_baseline_instance_id uuid,
    current_comparison_id uuid,
    top_finding_id uuid,
    last_reviewed_at timestamp(6) without time zone,
    watch_until timestamp(6) without time zone,
    resolved_at timestamp(6) without time zone,
    lock_version integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT cases_analysis_status_check CHECK ((analysis_status = ANY (ARRAY['not_started'::text, 'pending'::text, 'current'::text, 'stale'::text, 'failed'::text, 'insufficient_evidence'::text]))),
    CONSTRAINT cases_review_priority_check CHECK ((review_priority = ANY (ARRAY['now'::text, 'today'::text, 'routine'::text, 'watch'::text]))),
    CONSTRAINT cases_status_check CHECK ((status = ANY (ARRAY['new'::text, 'triaged'::text, 'investigating'::text, 'watching'::text, 'waiting_external'::text, 'resolved'::text, 'dismissed'::text])))
);


--
-- Name: derived_signals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.derived_signals (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    semantic_key text NOT NULL,
    semantic_version integer NOT NULL,
    window_started_at timestamp(6) without time zone NOT NULL,
    window_ended_at timestamp(6) without time zone NOT NULL,
    value_numeric numeric,
    value_text text,
    value_json jsonb,
    unit text,
    algorithm_key text NOT NULL,
    algorithm_version integer NOT NULL,
    algorithm_digest text NOT NULL,
    evidence_set_id uuid,
    usable_input_count integer DEFAULT 0 NOT NULL,
    raw_input_count integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'computed'::text NOT NULL,
    computed_at timestamp(6) without time zone NOT NULL,
    as_of timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT derived_signals_status_check CHECK ((status = ANY (ARRAY['computed'::text, 'insufficient_input'::text, 'superseded'::text, 'failed'::text]))),
    CONSTRAINT derived_signals_value_representation_check CHECK ((((status = 'computed'::text) AND ((value_numeric IS NOT NULL) OR (value_text IS NOT NULL) OR (value_json IS NOT NULL))) OR ((status <> 'computed'::text) AND (value_numeric IS NULL) AND (value_text IS NULL)))),
    CONSTRAINT derived_signals_window_order_check CHECK ((window_ended_at >= window_started_at))
);


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid,
    source_id uuid NOT NULL,
    external_id text NOT NULL,
    manufacturer text,
    model text,
    device_type text,
    firmware_version text,
    active_from timestamp(6) without time zone NOT NULL,
    active_to timestamp(6) without time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: domain_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.domain_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    aggregate_type text NOT NULL,
    aggregate_id uuid NOT NULL,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    dispatched_at timestamp(6) without time zone,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid DEFAULT uuidv7() NOT NULL,
    public_id text NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    semantic_key text NOT NULL,
    semantic_version integer NOT NULL,
    occurred_at timestamp(6) without time zone NOT NULL,
    ended_at timestamp(6) without time zone,
    source_id uuid NOT NULL,
    device_id uuid,
    raw_envelope_id uuid NOT NULL,
    recording_method text DEFAULT 'unknown'::text NOT NULL,
    attributes_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    normalizer_key text NOT NULL,
    normalizer_version integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: evidence_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evidence_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    evidence_set_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    record_type text NOT NULL,
    record_id uuid NOT NULL,
    role text DEFAULT 'input'::text NOT NULL,
    ordinal integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: evidence_sets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.evidence_sets (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    purpose text NOT NULL,
    as_of timestamp(6) without time zone NOT NULL,
    fingerprint text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT evidence_sets_purpose_check CHECK ((purpose = ANY (ARRAY['derived_signal_inputs'::text, 'context_inputs'::text, 'baseline_inputs'::text, 'comparison_affected_inputs'::text, 'comparison_baseline_inputs'::text, 'investigation_snapshot'::text])))
);


--
-- Name: intervals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.intervals (
    id uuid DEFAULT uuidv7() NOT NULL,
    public_id text NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    semantic_key text NOT NULL,
    semantic_version integer NOT NULL,
    started_at timestamp(6) without time zone NOT NULL,
    ended_at timestamp(6) without time zone,
    source_id uuid NOT NULL,
    raw_envelope_id uuid NOT NULL,
    attributes_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    normalizer_key text NOT NULL,
    normalizer_version integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT intervals_end_after_start_check CHECK (((ended_at IS NULL) OR (ended_at >= started_at)))
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    email_address text NOT NULL,
    role text NOT NULL,
    token_digest text NOT NULL,
    invited_by_id uuid NOT NULL,
    expires_at timestamp(6) without time zone NOT NULL,
    accepted_at timestamp(6) without time zone,
    accepted_by_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT invitations_role_check CHECK ((role = ANY (ARRAY['organization_admin'::text, 'clinical_ops'::text, 'clinician'::text, 'analyst'::text, 'support_limited'::text])))
);


--
-- Name: monitor_configurations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monitor_configurations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    domain_key text NOT NULL,
    monitor_key text NOT NULL,
    monitor_version integer NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    routing_parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: monitor_evaluations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.monitor_evaluations (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    monitor_key text NOT NULL,
    monitor_version integer NOT NULL,
    window_started_at timestamp(6) without time zone NOT NULL,
    window_ended_at timestamp(6) without time zone NOT NULL,
    evaluated_at timestamp(6) without time zone NOT NULL,
    result text NOT NULL,
    input_fingerprint text,
    details jsonb DEFAULT '{}'::jsonb NOT NULL,
    signal_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT monitor_evaluations_result_check CHECK ((result = ANY (ARRAY['triggered'::text, 'not_triggered'::text, 'insufficient_data'::text, 'skipped'::text, 'error'::text])))
);


--
-- Name: observation_groups; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observation_groups (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    semantic_key text NOT NULL,
    semantic_version integer NOT NULL,
    observed_at timestamp(6) without time zone NOT NULL,
    source_id uuid NOT NULL,
    raw_envelope_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observations (
    id uuid DEFAULT uuidv7() NOT NULL,
    public_id text NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    semantic_key text NOT NULL,
    semantic_version integer NOT NULL,
    observation_group_id uuid,
    value_numeric numeric,
    value_text text,
    value_code text,
    unit text,
    observed_at timestamp(6) without time zone NOT NULL,
    observed_end_at timestamp(6) without time zone,
    timezone_offset_minutes integer,
    source_id uuid NOT NULL,
    device_id uuid,
    raw_envelope_id uuid NOT NULL,
    source_record_id text NOT NULL,
    recording_method text DEFAULT 'unknown'::text NOT NULL,
    measurement_protocol text,
    quality_state text DEFAULT 'observed'::text NOT NULL,
    quality_flags jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_modified_at timestamp(6) without time zone,
    ingested_at timestamp(6) without time zone,
    normalized_at timestamp(6) without time zone NOT NULL,
    normalizer_key text NOT NULL,
    normalizer_version integer NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT observations_numeric_requires_unit_check CHECK (((value_numeric IS NULL) OR (unit IS NOT NULL))),
    CONSTRAINT observations_quality_state_check CHECK ((quality_state = ANY (ARRAY['observed'::text, 'not_expected'::text, 'expected_but_missing'::text, 'source_unavailable'::text, 'device_not_reporting'::text, 'manual_entry_absent'::text, 'invalid_measurement'::text, 'excluded_by_rule'::text, 'late_not_yet_arrived'::text, 'unknown'::text]))),
    CONSTRAINT observations_recording_method_check CHECK ((recording_method = ANY (ARRAY['device_automatic'::text, 'device_manual_transcription'::text, 'manual_entry'::text, 'clinician_entered'::text, 'imported_batch'::text, 'unknown'::text]))),
    CONSTRAINT observations_value_representation_check CHECK ((((quality_state = 'observed'::text) AND (((((value_numeric IS NOT NULL))::integer + ((value_text IS NOT NULL))::integer) + ((value_code IS NOT NULL))::integer) = 1)) OR ((quality_state <> 'observed'::text) AND (value_numeric IS NULL) AND (value_text IS NULL) AND (value_code IS NULL))))
);


--
-- Name: organization_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_memberships (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    invited_at timestamp(6) without time zone,
    joined_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT organization_memberships_role_check CHECK ((role = ANY (ARRAY['organization_admin'::text, 'clinical_ops'::text, 'clinician'::text, 'analyst'::text, 'support_limited'::text]))),
    CONSTRAINT organization_memberships_status_check CHECK ((status = ANY (ARRAY['invited'::text, 'active'::text, 'suspended'::text])))
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT uuidv7() NOT NULL,
    name text NOT NULL,
    slug text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT organizations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'suspended'::text])))
);


--
-- Name: raw_envelopes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.raw_envelopes (
    id uuid DEFAULT uuidv7() NOT NULL,
    public_id text NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid,
    source_id uuid NOT NULL,
    source_record_id text NOT NULL,
    source_record_version text,
    content_type text NOT NULL,
    object_key text NOT NULL,
    content_hash text NOT NULL,
    observed_at timestamp(6) without time zone,
    source_modified_at timestamp(6) without time zone,
    received_at timestamp(6) without time zone NOT NULL,
    ingested_at timestamp(6) without time zone,
    adapter_key text NOT NULL,
    adapter_version text NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
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
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    ip_address text,
    user_agent text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: signals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.signals (
    id uuid DEFAULT uuidv7() NOT NULL,
    public_id text NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    monitor_key text NOT NULL,
    monitor_version integer NOT NULL,
    monitor_digest text NOT NULL,
    signal_type text NOT NULL,
    domain_key text NOT NULL,
    detected_at timestamp(6) without time zone NOT NULL,
    window_started_at timestamp(6) without time zone NOT NULL,
    window_ended_at timestamp(6) without time zone,
    severity text DEFAULT 'info'::text NOT NULL,
    attributes_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    source_record_type text,
    source_record_id uuid,
    deduplication_key text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT signals_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'low'::text, 'moderate'::text, 'high'::text])))
);


--
-- Name: sources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sources (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    key text NOT NULL,
    source_type text NOT NULL,
    display_name text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    configuration_encrypted text,
    last_success_at timestamp(6) without time zone,
    last_failure_at timestamp(6) without time zone,
    last_failure_reason text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT sources_source_type_check CHECK ((source_type = ANY (ARRAY['synthetic'::text, 'csv_import'::text, 'customer_api'::text, 'fhir'::text, 'device_cloud'::text, 'rpm_vendor'::text, 'manual'::text]))),
    CONSTRAINT sources_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'disabled'::text])))
);


--
-- Name: staff_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_members (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    granted_at timestamp(6) without time zone NOT NULL,
    granted_by_id uuid,
    revoked_at timestamp(6) without time zone,
    note text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT staff_members_status_check CHECK ((status = ANY (ARRAY['active'::text, 'revoked'::text])))
);


--
-- Name: subject_identifiers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject_identifiers (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    system text NOT NULL,
    value text NOT NULL,
    source_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: subject_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subject_identities (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    subject_id uuid NOT NULL,
    display_name text,
    first_name text,
    last_name text,
    date_of_birth text,
    contact_email text,
    contact_phone text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: subjects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subjects (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    public_id text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT subjects_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text])))
);


--
-- Name: team_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_memberships (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    team_id uuid NOT NULL,
    organization_membership_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    name text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT teams_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archived'::text])))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT uuidv7() NOT NULL,
    email_address text NOT NULL,
    password_digest text NOT NULL,
    full_name text,
    status text DEFAULT 'active'::text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT users_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text])))
);


--
-- Name: watch_conditions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.watch_conditions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    case_id uuid NOT NULL,
    created_by_id uuid,
    condition_type text NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    expires_at timestamp(6) without time zone,
    satisfied_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT watch_conditions_condition_type_check CHECK ((condition_type = ANY (ARRAY['time_elapsed'::text, 'new_observation_count'::text, 'new_signal'::text, 'threshold_crossed'::text])))
);


--
-- Name: workflow_actions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.workflow_actions (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_id uuid NOT NULL,
    case_id uuid NOT NULL,
    requested_by_id uuid,
    action_type text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    parameters jsonb DEFAULT '{}'::jsonb NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    idempotency_key text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text,
    dispatched_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT workflow_actions_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'dispatched'::text, 'succeeded'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: case_correlation_scopes case_correlation_scopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_correlation_scopes
    ADD CONSTRAINT case_correlation_scopes_pkey PRIMARY KEY (id);


--
-- Name: case_dispositions case_dispositions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_dispositions
    ADD CONSTRAINT case_dispositions_pkey PRIMARY KEY (id);


--
-- Name: case_events case_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_events
    ADD CONSTRAINT case_events_pkey PRIMARY KEY (id);


--
-- Name: case_signals case_signals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_signals
    ADD CONSTRAINT case_signals_pkey PRIMARY KEY (id);


--
-- Name: cases cases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT cases_pkey PRIMARY KEY (id);


--
-- Name: derived_signals derived_signals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_signals
    ADD CONSTRAINT derived_signals_pkey PRIMARY KEY (id);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: domain_events domain_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_events
    ADD CONSTRAINT domain_events_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: evidence_items evidence_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_items
    ADD CONSTRAINT evidence_items_pkey PRIMARY KEY (id);


--
-- Name: evidence_sets evidence_sets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_sets
    ADD CONSTRAINT evidence_sets_pkey PRIMARY KEY (id);


--
-- Name: intervals intervals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals
    ADD CONSTRAINT intervals_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: monitor_configurations monitor_configurations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitor_configurations
    ADD CONSTRAINT monitor_configurations_pkey PRIMARY KEY (id);


--
-- Name: monitor_evaluations monitor_evaluations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitor_evaluations
    ADD CONSTRAINT monitor_evaluations_pkey PRIMARY KEY (id);


--
-- Name: observation_groups observation_groups_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observation_groups
    ADD CONSTRAINT observation_groups_pkey PRIMARY KEY (id);


--
-- Name: observations observations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT observations_pkey PRIMARY KEY (id);


--
-- Name: organization_memberships organization_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: raw_envelopes raw_envelopes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_envelopes
    ADD CONSTRAINT raw_envelopes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: signals signals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signals
    ADD CONSTRAINT signals_pkey PRIMARY KEY (id);


--
-- Name: sources sources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT sources_pkey PRIMARY KEY (id);


--
-- Name: staff_members staff_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_members
    ADD CONSTRAINT staff_members_pkey PRIMARY KEY (id);


--
-- Name: subject_identifiers subject_identifiers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_identifiers
    ADD CONSTRAINT subject_identifiers_pkey PRIMARY KEY (id);


--
-- Name: subject_identities subject_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_identities
    ADD CONSTRAINT subject_identities_pkey PRIMARY KEY (id);


--
-- Name: subjects subjects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subjects
    ADD CONSTRAINT subjects_pkey PRIMARY KEY (id);


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
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: watch_conditions watch_conditions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watch_conditions
    ADD CONSTRAINT watch_conditions_pkey PRIMARY KEY (id);


--
-- Name: workflow_actions workflow_actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_actions
    ADD CONSTRAINT workflow_actions_pkey PRIMARY KEY (id);


--
-- Name: index_audit_events_on_actor_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_actor_and_time ON public.audit_events USING btree (actor_id, occurred_at);


--
-- Name: index_audit_events_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_actor_id ON public.audit_events USING btree (actor_id);


--
-- Name: index_audit_events_on_org_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_org_and_time ON public.audit_events USING btree (organization_id, occurred_at);


--
-- Name: index_audit_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_organization_id ON public.audit_events USING btree (organization_id);


--
-- Name: index_audit_events_on_staff_member_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_staff_member_id ON public.audit_events USING btree (staff_member_id);


--
-- Name: index_audit_events_on_type_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_audit_events_on_type_and_time ON public.audit_events USING btree (event_type, occurred_at);


--
-- Name: index_case_correlation_scopes_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_case_correlation_scopes_identity ON public.case_correlation_scopes USING btree (organization_id, subject_id, domain_key);


--
-- Name: index_case_correlation_scopes_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_correlation_scopes_on_organization_id ON public.case_correlation_scopes USING btree (organization_id);


--
-- Name: index_case_correlation_scopes_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_correlation_scopes_on_subject_id ON public.case_correlation_scopes USING btree (subject_id);


--
-- Name: index_case_dispositions_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_dispositions_on_actor_id ON public.case_dispositions USING btree (actor_id);


--
-- Name: index_case_dispositions_on_case_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_dispositions_on_case_and_time ON public.case_dispositions USING btree (case_id, disposed_at);


--
-- Name: index_case_dispositions_on_case_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_dispositions_on_case_id ON public.case_dispositions USING btree (case_id);


--
-- Name: index_case_dispositions_on_org_code_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_dispositions_on_org_code_time ON public.case_dispositions USING btree (organization_id, code, disposed_at);


--
-- Name: index_case_dispositions_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_dispositions_on_organization_id ON public.case_dispositions USING btree (organization_id);


--
-- Name: index_case_events_on_case_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_events_on_case_and_time ON public.case_events USING btree (case_id, occurred_at);


--
-- Name: index_case_events_on_case_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_events_on_case_id ON public.case_events USING btree (case_id);


--
-- Name: index_case_events_on_org_type_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_events_on_org_type_time ON public.case_events USING btree (organization_id, event_type, occurred_at);


--
-- Name: index_case_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_events_on_organization_id ON public.case_events USING btree (organization_id);


--
-- Name: index_case_signals_on_case_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_signals_on_case_id ON public.case_signals USING btree (case_id);


--
-- Name: index_case_signals_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_signals_on_organization_id ON public.case_signals USING btree (organization_id);


--
-- Name: index_case_signals_on_signal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_signals_on_signal ON public.case_signals USING btree (signal_id);


--
-- Name: index_case_signals_on_signal_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_case_signals_on_signal_id ON public.case_signals USING btree (signal_id);


--
-- Name: index_case_signals_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_case_signals_unique ON public.case_signals USING btree (case_id, signal_id);


--
-- Name: index_cases_on_org_owner_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_org_owner_status ON public.cases USING btree (organization_id, owner_id, status);


--
-- Name: index_cases_on_org_status_priority_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_org_status_priority_time ON public.cases USING btree (organization_id, status, review_priority, detected_at);


--
-- Name: index_cases_on_org_subject_domain_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_org_subject_domain_status ON public.cases USING btree (organization_id, subject_id, domain_key, status);


--
-- Name: index_cases_on_org_team_status_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_org_team_status_priority ON public.cases USING btree (organization_id, team_id, status, review_priority);


--
-- Name: index_cases_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_organization_id ON public.cases USING btree (organization_id);


--
-- Name: index_cases_on_organization_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cases_on_organization_id_and_public_id ON public.cases USING btree (organization_id, public_id);


--
-- Name: index_cases_on_owner_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_owner_id ON public.cases USING btree (owner_id);


--
-- Name: index_cases_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_subject_id ON public.cases USING btree (subject_id);


--
-- Name: index_cases_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cases_on_team_id ON public.cases USING btree (team_id);


--
-- Name: index_derived_signals_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_derived_signals_identity ON public.derived_signals USING btree (organization_id, subject_id, semantic_key, semantic_version, window_started_at, window_ended_at, algorithm_version);


--
-- Name: index_derived_signals_on_evidence_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_derived_signals_on_evidence_set_id ON public.derived_signals USING btree (evidence_set_id);


--
-- Name: index_derived_signals_on_org_subject_key_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_derived_signals_on_org_subject_key_time ON public.derived_signals USING btree (organization_id, subject_id, semantic_key, window_ended_at DESC);


--
-- Name: index_derived_signals_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_derived_signals_on_organization_id ON public.derived_signals USING btree (organization_id);


--
-- Name: index_derived_signals_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_derived_signals_on_subject_id ON public.derived_signals USING btree (subject_id);


--
-- Name: index_devices_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_devices_identity ON public.devices USING btree (organization_id, source_id, external_id);


--
-- Name: index_devices_on_org_subject_active_from; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_org_subject_active_from ON public.devices USING btree (organization_id, subject_id, active_from);


--
-- Name: index_devices_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_organization_id ON public.devices USING btree (organization_id);


--
-- Name: index_devices_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_source_id ON public.devices USING btree (source_id);


--
-- Name: index_devices_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_devices_on_subject_id ON public.devices USING btree (subject_id);


--
-- Name: index_domain_events_on_aggregate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_domain_events_on_aggregate ON public.domain_events USING btree (organization_id, aggregate_type, aggregate_id, occurred_at);


--
-- Name: index_domain_events_on_org_and_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_domain_events_on_org_and_type ON public.domain_events USING btree (organization_id, event_type, occurred_at);


--
-- Name: index_domain_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_domain_events_on_organization_id ON public.domain_events USING btree (organization_id);


--
-- Name: index_domain_events_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_domain_events_pending ON public.domain_events USING btree (occurred_at, id) WHERE (dispatched_at IS NULL);


--
-- Name: index_events_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_device_id ON public.events USING btree (device_id);


--
-- Name: index_events_on_org_subject_key_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_org_subject_key_time ON public.events USING btree (organization_id, subject_id, semantic_key, occurred_at DESC);


--
-- Name: index_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_organization_id ON public.events USING btree (organization_id);


--
-- Name: index_events_on_organization_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_events_on_organization_id_and_public_id ON public.events USING btree (organization_id, public_id);


--
-- Name: index_events_on_raw_envelope_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_raw_envelope_id ON public.events USING btree (raw_envelope_id);


--
-- Name: index_events_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_source_id ON public.events USING btree (source_id);


--
-- Name: index_events_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_subject_id ON public.events USING btree (subject_id);


--
-- Name: index_evidence_items_on_evidence_set_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_items_on_evidence_set_id ON public.evidence_items USING btree (evidence_set_id);


--
-- Name: index_evidence_items_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_items_on_organization_id ON public.evidence_items USING btree (organization_id);


--
-- Name: index_evidence_items_on_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_items_on_record ON public.evidence_items USING btree (organization_id, record_type, record_id);


--
-- Name: index_evidence_items_on_set_and_ordinal; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_items_on_set_and_ordinal ON public.evidence_items USING btree (evidence_set_id, ordinal);


--
-- Name: index_evidence_items_unique_per_set; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_evidence_items_unique_per_set ON public.evidence_items USING btree (evidence_set_id, record_type, record_id, role);


--
-- Name: index_evidence_sets_on_org_purpose_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_sets_on_org_purpose_fingerprint ON public.evidence_sets USING btree (organization_id, purpose, fingerprint);


--
-- Name: index_evidence_sets_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_evidence_sets_on_organization_id ON public.evidence_sets USING btree (organization_id);


--
-- Name: index_intervals_on_org_subject_key_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_intervals_on_org_subject_key_time ON public.intervals USING btree (organization_id, subject_id, semantic_key, started_at DESC);


--
-- Name: index_intervals_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_intervals_on_organization_id ON public.intervals USING btree (organization_id);


--
-- Name: index_intervals_on_organization_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_intervals_on_organization_id_and_public_id ON public.intervals USING btree (organization_id, public_id);


--
-- Name: index_intervals_on_raw_envelope_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_intervals_on_raw_envelope_id ON public.intervals USING btree (raw_envelope_id);


--
-- Name: index_intervals_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_intervals_on_source_id ON public.intervals USING btree (source_id);


--
-- Name: index_intervals_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_intervals_on_subject_id ON public.intervals USING btree (subject_id);


--
-- Name: index_invitations_on_accepted_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_accepted_by_id ON public.invitations USING btree (accepted_by_id);


--
-- Name: index_invitations_on_invited_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_invited_by_id ON public.invitations USING btree (invited_by_id);


--
-- Name: index_invitations_on_org_and_email_outstanding; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_org_and_email_outstanding ON public.invitations USING btree (organization_id, email_address) WHERE (accepted_at IS NULL);


--
-- Name: index_invitations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_organization_id ON public.invitations USING btree (organization_id);


--
-- Name: index_invitations_on_token_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_token_digest ON public.invitations USING btree (token_digest);


--
-- Name: index_monitor_configurations_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_monitor_configurations_identity ON public.monitor_configurations USING btree (organization_id, monitor_key, monitor_version);


--
-- Name: index_monitor_configurations_on_org_domain_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monitor_configurations_on_org_domain_enabled ON public.monitor_configurations USING btree (organization_id, domain_key, enabled);


--
-- Name: index_monitor_configurations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monitor_configurations_on_organization_id ON public.monitor_configurations USING btree (organization_id);


--
-- Name: index_monitor_evaluations_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monitor_evaluations_lookup ON public.monitor_evaluations USING btree (organization_id, subject_id, monitor_key, evaluated_at DESC);


--
-- Name: index_monitor_evaluations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monitor_evaluations_on_organization_id ON public.monitor_evaluations USING btree (organization_id);


--
-- Name: index_monitor_evaluations_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_monitor_evaluations_on_subject_id ON public.monitor_evaluations USING btree (subject_id);


--
-- Name: index_observation_groups_on_org_subject_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observation_groups_on_org_subject_time ON public.observation_groups USING btree (organization_id, subject_id, observed_at);


--
-- Name: index_observation_groups_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observation_groups_on_organization_id ON public.observation_groups USING btree (organization_id);


--
-- Name: index_observation_groups_on_raw_envelope_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observation_groups_on_raw_envelope_id ON public.observation_groups USING btree (raw_envelope_id);


--
-- Name: index_observation_groups_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observation_groups_on_source_id ON public.observation_groups USING btree (source_id);


--
-- Name: index_observation_groups_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observation_groups_on_subject_id ON public.observation_groups USING btree (subject_id);


--
-- Name: index_observations_normalization_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_observations_normalization_identity ON public.observations USING btree (raw_envelope_id, semantic_key, semantic_version, normalizer_version, observed_at);


--
-- Name: index_observations_on_device_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_device_id ON public.observations USING btree (device_id);


--
-- Name: index_observations_on_observation_group_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_observation_group_id ON public.observations USING btree (observation_group_id);


--
-- Name: index_observations_on_org_source_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_org_source_record ON public.observations USING btree (organization_id, source_id, source_record_id);


--
-- Name: index_observations_on_org_subject_key_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_org_subject_key_time ON public.observations USING btree (organization_id, subject_id, semantic_key, observed_at DESC);


--
-- Name: index_observations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_organization_id ON public.observations USING btree (organization_id);


--
-- Name: index_observations_on_organization_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_observations_on_organization_id_and_public_id ON public.observations USING btree (organization_id, public_id);


--
-- Name: index_observations_on_raw_envelope_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_raw_envelope_id ON public.observations USING btree (raw_envelope_id);


--
-- Name: index_observations_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_source_id ON public.observations USING btree (source_id);


--
-- Name: index_observations_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_observations_on_subject_id ON public.observations USING btree (subject_id);


--
-- Name: index_org_memberships_on_org_and_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_org_memberships_on_org_and_role ON public.organization_memberships USING btree (organization_id, role);


--
-- Name: index_org_memberships_on_org_and_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_org_memberships_on_org_and_user ON public.organization_memberships USING btree (organization_id, user_id);


--
-- Name: index_organization_memberships_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_organization_id ON public.organization_memberships USING btree (organization_id);


--
-- Name: index_organization_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_user_id ON public.organization_memberships USING btree (user_id);


--
-- Name: index_organizations_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_slug ON public.organizations USING btree (slug);


--
-- Name: index_raw_envelopes_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_raw_envelopes_identity ON public.raw_envelopes USING btree (organization_id, source_id, source_record_id, source_record_version) NULLS NOT DISTINCT;


--
-- Name: index_raw_envelopes_on_org_subject_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_raw_envelopes_on_org_subject_time ON public.raw_envelopes USING btree (organization_id, subject_id, observed_at);


--
-- Name: index_raw_envelopes_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_raw_envelopes_on_organization_id ON public.raw_envelopes USING btree (organization_id);


--
-- Name: index_raw_envelopes_on_organization_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_raw_envelopes_on_organization_id_and_public_id ON public.raw_envelopes USING btree (organization_id, public_id);


--
-- Name: index_raw_envelopes_on_organization_id_and_received_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_raw_envelopes_on_organization_id_and_received_at ON public.raw_envelopes USING btree (organization_id, received_at);


--
-- Name: index_raw_envelopes_on_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_raw_envelopes_on_source_id ON public.raw_envelopes USING btree (source_id);


--
-- Name: index_raw_envelopes_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_raw_envelopes_on_subject_id ON public.raw_envelopes USING btree (subject_id);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_signals_on_org_and_dedupe_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_signals_on_org_and_dedupe_key ON public.signals USING btree (organization_id, deduplication_key);


--
-- Name: index_signals_on_org_subject_domain_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_signals_on_org_subject_domain_time ON public.signals USING btree (organization_id, subject_id, domain_key, detected_at DESC);


--
-- Name: index_signals_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_signals_on_organization_id ON public.signals USING btree (organization_id);


--
-- Name: index_signals_on_organization_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_signals_on_organization_id_and_public_id ON public.signals USING btree (organization_id, public_id);


--
-- Name: index_signals_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_signals_on_subject_id ON public.signals USING btree (subject_id);


--
-- Name: index_sources_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sources_on_organization_id ON public.sources USING btree (organization_id);


--
-- Name: index_sources_on_organization_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sources_on_organization_id_and_key ON public.sources USING btree (organization_id, key);


--
-- Name: index_sources_on_organization_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sources_on_organization_id_and_status ON public.sources USING btree (organization_id, status);


--
-- Name: index_staff_members_on_granted_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_staff_members_on_granted_by_id ON public.staff_members USING btree (granted_by_id);


--
-- Name: index_staff_members_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_staff_members_on_user_id ON public.staff_members USING btree (user_id);


--
-- Name: index_subject_identifiers_on_org_and_subject; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subject_identifiers_on_org_and_subject ON public.subject_identifiers USING btree (organization_id, subject_id);


--
-- Name: index_subject_identifiers_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subject_identifiers_on_organization_id ON public.subject_identifiers USING btree (organization_id);


--
-- Name: index_subject_identifiers_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subject_identifiers_on_subject_id ON public.subject_identifiers USING btree (subject_id);


--
-- Name: index_subject_identifiers_unique_per_org; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subject_identifiers_unique_per_org ON public.subject_identifiers USING btree (organization_id, system, value);


--
-- Name: index_subject_identities_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subject_identities_on_organization_id ON public.subject_identities USING btree (organization_id);


--
-- Name: index_subject_identities_on_subject_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subject_identities_on_subject_id ON public.subject_identities USING btree (subject_id);


--
-- Name: index_subjects_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subjects_on_organization_id ON public.subjects USING btree (organization_id);


--
-- Name: index_subjects_on_organization_id_and_public_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_subjects_on_organization_id_and_public_id ON public.subjects USING btree (organization_id, public_id);


--
-- Name: index_subjects_on_organization_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_subjects_on_organization_id_and_status ON public.subjects USING btree (organization_id, status);


--
-- Name: index_team_memberships_on_org_and_team; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_org_and_team ON public.team_memberships USING btree (organization_id, team_id);


--
-- Name: index_team_memberships_on_org_membership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_org_membership_id ON public.team_memberships USING btree (organization_membership_id);


--
-- Name: index_team_memberships_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_organization_id ON public.team_memberships USING btree (organization_id);


--
-- Name: index_team_memberships_on_team_and_membership; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_memberships_on_team_and_membership ON public.team_memberships USING btree (team_id, organization_membership_id);


--
-- Name: index_team_memberships_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_team_id ON public.team_memberships USING btree (team_id);


--
-- Name: index_teams_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teams_on_organization_id ON public.teams USING btree (organization_id);


--
-- Name: index_teams_on_organization_id_and_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_organization_id_and_name ON public.teams USING btree (organization_id, name);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: index_watch_conditions_on_case_and_satisfied; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_watch_conditions_on_case_and_satisfied ON public.watch_conditions USING btree (case_id, satisfied_at);


--
-- Name: index_watch_conditions_on_case_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_watch_conditions_on_case_id ON public.watch_conditions USING btree (case_id);


--
-- Name: index_watch_conditions_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_watch_conditions_on_created_by_id ON public.watch_conditions USING btree (created_by_id);


--
-- Name: index_watch_conditions_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_watch_conditions_on_organization_id ON public.watch_conditions USING btree (organization_id);


--
-- Name: index_watch_conditions_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_watch_conditions_pending ON public.watch_conditions USING btree (organization_id, expires_at) WHERE (satisfied_at IS NULL);


--
-- Name: index_workflow_actions_idempotency; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_workflow_actions_idempotency ON public.workflow_actions USING btree (organization_id, idempotency_key);


--
-- Name: index_workflow_actions_on_case_and_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_actions_on_case_and_time ON public.workflow_actions USING btree (case_id, created_at);


--
-- Name: index_workflow_actions_on_case_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_actions_on_case_id ON public.workflow_actions USING btree (case_id);


--
-- Name: index_workflow_actions_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_actions_on_organization_id ON public.workflow_actions USING btree (organization_id);


--
-- Name: index_workflow_actions_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_workflow_actions_on_requested_by_id ON public.workflow_actions USING btree (requested_by_id);


--
-- Name: subject_identifiers fk_rails_038ebe50fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_identifiers
    ADD CONSTRAINT fk_rails_038ebe50fb FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: evidence_items fk_rails_03f3451d9e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_items
    ADD CONSTRAINT fk_rails_03f3451d9e FOREIGN KEY (evidence_set_id) REFERENCES public.evidence_sets(id);


--
-- Name: raw_envelopes fk_rails_04cab64491; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_envelopes
    ADD CONSTRAINT fk_rails_04cab64491 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: case_events fk_rails_07cba11f9a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_events
    ADD CONSTRAINT fk_rails_07cba11f9a FOREIGN KEY (case_id) REFERENCES public.cases(id);


--
-- Name: evidence_sets fk_rails_0b249d477f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_sets
    ADD CONSTRAINT fk_rails_0b249d477f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: observations fk_rails_0dc011e4e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT fk_rails_0dc011e4e5 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: invitations fk_rails_0fe4c14f0e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_0fe4c14f0e FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: events fk_rails_163b5130b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_163b5130b5 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: observations fk_rails_1b0021e77f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT fk_rails_1b0021e77f FOREIGN KEY (raw_envelope_id) REFERENCES public.raw_envelopes(id);


--
-- Name: case_signals fk_rails_1cf1caeb0a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_signals
    ADD CONSTRAINT fk_rails_1cf1caeb0a FOREIGN KEY (case_id) REFERENCES public.cases(id);


--
-- Name: events fk_rails_1fda79cf5a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_1fda79cf5a FOREIGN KEY (raw_envelope_id) REFERENCES public.raw_envelopes(id);


--
-- Name: events fk_rails_201ad5ebff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_201ad5ebff FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: intervals fk_rails_2211a4c606; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals
    ADD CONSTRAINT fk_rails_2211a4c606 FOREIGN KEY (raw_envelope_id) REFERENCES public.raw_envelopes(id);


--
-- Name: signals fk_rails_247f220cd3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signals
    ADD CONSTRAINT fk_rails_247f220cd3 FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: derived_signals fk_rails_2554361053; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_signals
    ADD CONSTRAINT fk_rails_2554361053 FOREIGN KEY (evidence_set_id) REFERENCES public.evidence_sets(id);


--
-- Name: staff_members fk_rails_2925f894a8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_members
    ADD CONSTRAINT fk_rails_2925f894a8 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: case_dispositions fk_rails_31dfb9bb91; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_dispositions
    ADD CONSTRAINT fk_rails_31dfb9bb91 FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: watch_conditions fk_rails_32d123ef4d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watch_conditions
    ADD CONSTRAINT fk_rails_32d123ef4d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: invitations fk_rails_3d8c31759f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_3d8c31759f FOREIGN KEY (accepted_by_id) REFERENCES public.users(id);


--
-- Name: audit_events fk_rails_4463a8ee29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_rails_4463a8ee29 FOREIGN KEY (staff_member_id) REFERENCES public.staff_members(id);


--
-- Name: workflow_actions fk_rails_44659725be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_actions
    ADD CONSTRAINT fk_rails_44659725be FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: watch_conditions fk_rails_4701996be0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watch_conditions
    ADD CONSTRAINT fk_rails_4701996be0 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: sources fk_rails_4b1bec7af5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sources
    ADD CONSTRAINT fk_rails_4b1bec7af5 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: observations fk_rails_55688bc20c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT fk_rails_55688bc20c FOREIGN KEY (device_id) REFERENCES public.devices(id);


--
-- Name: organization_memberships fk_rails_57cf70d280; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT fk_rails_57cf70d280 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: monitor_configurations fk_rails_5aa0891e52; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitor_configurations
    ADD CONSTRAINT fk_rails_5aa0891e52 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: monitor_evaluations fk_rails_60bb870f93; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitor_evaluations
    ADD CONSTRAINT fk_rails_60bb870f93 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: team_memberships fk_rails_61c29b529e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_61c29b529e FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: observation_groups fk_rails_62b87b0c82; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observation_groups
    ADD CONSTRAINT fk_rails_62b87b0c82 FOREIGN KEY (raw_envelope_id) REFERENCES public.raw_envelopes(id);


--
-- Name: events fk_rails_635245fc67; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_635245fc67 FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: monitor_evaluations fk_rails_64cd3b3e64; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitor_evaluations
    ADD CONSTRAINT fk_rails_64cd3b3e64 FOREIGN KEY (signal_id) REFERENCES public.signals(id);


--
-- Name: evidence_items fk_rails_69ea66f966; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.evidence_items
    ADD CONSTRAINT fk_rails_69ea66f966 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: events fk_rails_6a6456eb31; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_6a6456eb31 FOREIGN KEY (device_id) REFERENCES public.devices(id);


--
-- Name: raw_envelopes fk_rails_6b257aa36a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_envelopes
    ADD CONSTRAINT fk_rails_6b257aa36a FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: monitor_evaluations fk_rails_6c174689f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.monitor_evaluations
    ADD CONSTRAINT fk_rails_6c174689f9 FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: team_memberships fk_rails_6dfe318707; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_6dfe318707 FOREIGN KEY (organization_membership_id) REFERENCES public.organization_memberships(id);


--
-- Name: organization_memberships fk_rails_715ab7f4fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT fk_rails_715ab7f4fe FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: raw_envelopes fk_rails_745563aca1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_envelopes
    ADD CONSTRAINT fk_rails_745563aca1 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: case_signals fk_rails_7aeeb938f9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_signals
    ADD CONSTRAINT fk_rails_7aeeb938f9 FOREIGN KEY (signal_id) REFERENCES public.signals(id);


--
-- Name: subject_identifiers fk_rails_7d53575fbf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_identifiers
    ADD CONSTRAINT fk_rails_7d53575fbf FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: staff_members fk_rails_81a4d9ebe4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_members
    ADD CONSTRAINT fk_rails_81a4d9ebe4 FOREIGN KEY (granted_by_id) REFERENCES public.users(id);


--
-- Name: case_signals fk_rails_8429d96d34; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_signals
    ADD CONSTRAINT fk_rails_8429d96d34 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: domain_events fk_rails_8afe43432b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_events
    ADD CONSTRAINT fk_rails_8afe43432b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: watch_conditions fk_rails_8c8e83d5d7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.watch_conditions
    ADD CONSTRAINT fk_rails_8c8e83d5d7 FOREIGN KEY (case_id) REFERENCES public.cases(id);


--
-- Name: cases fk_rails_8ffced78ef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT fk_rails_8ffced78ef FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: workflow_actions fk_rails_934b0cf43e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_actions
    ADD CONSTRAINT fk_rails_934b0cf43e FOREIGN KEY (case_id) REFERENCES public.cases(id);


--
-- Name: devices fk_rails_9957830653; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT fk_rails_9957830653 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: subjects fk_rails_9bd688ebfe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subjects
    ADD CONSTRAINT fk_rails_9bd688ebfe FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: derived_signals fk_rails_9d20e5fb0b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_signals
    ADD CONSTRAINT fk_rails_9d20e5fb0b FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: case_correlation_scopes fk_rails_a2f11c5c85; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_correlation_scopes
    ADD CONSTRAINT fk_rails_a2f11c5c85 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: cases fk_rails_a2f743c059; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT fk_rails_a2f743c059 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: observation_groups fk_rails_a4d23a4737; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observation_groups
    ADD CONSTRAINT fk_rails_a4d23a4737 FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: derived_signals fk_rails_b1e4d6b690; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.derived_signals
    ADD CONSTRAINT fk_rails_b1e4d6b690 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: intervals fk_rails_b44d37140b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals
    ADD CONSTRAINT fk_rails_b44d37140b FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: observations fk_rails_b5029132a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT fk_rails_b5029132a6 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: subject_identities fk_rails_b620b4b32c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_identities
    ADD CONSTRAINT fk_rails_b620b4b32c FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: audit_events fk_rails_be0ed9e37f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_rails_be0ed9e37f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: observation_groups fk_rails_c7842aa92b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observation_groups
    ADD CONSTRAINT fk_rails_c7842aa92b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: case_events fk_rails_c792ddd48a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_events
    ADD CONSTRAINT fk_rails_c792ddd48a FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: workflow_actions fk_rails_ca0f033096; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.workflow_actions
    ADD CONSTRAINT fk_rails_ca0f033096 FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: observation_groups fk_rails_caaaf09583; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observation_groups
    ADD CONSTRAINT fk_rails_caaaf09583 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- Name: signals fk_rails_cebf70b0e3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.signals
    ADD CONSTRAINT fk_rails_cebf70b0e3 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: cases fk_rails_d042fd9680; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT fk_rails_d042fd9680 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: cases fk_rails_d192f7ddcd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cases
    ADD CONSTRAINT fk_rails_d192f7ddcd FOREIGN KEY (owner_id) REFERENCES public.users(id);


--
-- Name: case_dispositions fk_rails_d685bdc944; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_dispositions
    ADD CONSTRAINT fk_rails_d685bdc944 FOREIGN KEY (case_id) REFERENCES public.cases(id);


--
-- Name: invitations fk_rails_d799c974a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_d799c974a1 FOREIGN KEY (invited_by_id) REFERENCES public.users(id);


--
-- Name: audit_events fk_rails_dd1f3a471a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_events
    ADD CONSTRAINT fk_rails_dd1f3a471a FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: devices fk_rails_de2d742c51; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT fk_rails_de2d742c51 FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: case_correlation_scopes fk_rails_e7c8800882; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_correlation_scopes
    ADD CONSTRAINT fk_rails_e7c8800882 FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: subject_identities fk_rails_e961cc75df; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_identities
    ADD CONSTRAINT fk_rails_e961cc75df FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: intervals fk_rails_ee0738fd83; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals
    ADD CONSTRAINT fk_rails_ee0738fd83 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: teams fk_rails_f07f0bd66d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_f07f0bd66d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: devices fk_rails_f102621b29; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT fk_rails_f102621b29 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: observations fk_rails_f73dd91004; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT fk_rails_f73dd91004 FOREIGN KEY (observation_group_id) REFERENCES public.observation_groups(id);


--
-- Name: team_memberships fk_rails_f815fd92e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_f815fd92e5 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: observations fk_rails_f83a97befd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observations
    ADD CONSTRAINT fk_rails_f83a97befd FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


--
-- Name: case_dispositions fk_rails_fe43aebec9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.case_dispositions
    ADD CONSTRAINT fk_rails_fe43aebec9 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: intervals fk_rails_ffb9e40026; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals
    ADD CONSTRAINT fk_rails_ffb9e40026 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260809160000'),
('20260809140000'),
('20260809130000'),
('20260809120100'),
('20260809120000'),
('20260809110300'),
('20260809110200'),
('20260809110100'),
('20260809110000'),
('20260809100100'),
('20260809100000'),
('20260809090200'),
('20260809090100'),
('20260809090000'),
('20260809080100'),
('20260809080000'),
('20260809071500'),
('20260809065957'),
('20260809065956'),
('20260809065955'),
('20260809065954'),
('20260809065953'),
('20260809065952'),
('20260809065950');

