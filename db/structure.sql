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
-- Name: subject_identifiers fk_rails_038ebe50fb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subject_identifiers
    ADD CONSTRAINT fk_rails_038ebe50fb FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: raw_envelopes fk_rails_04cab64491; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.raw_envelopes
    ADD CONSTRAINT fk_rails_04cab64491 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: staff_members fk_rails_2925f894a8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_members
    ADD CONSTRAINT fk_rails_2925f894a8 FOREIGN KEY (user_id) REFERENCES public.users(id);


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
-- Name: domain_events fk_rails_8afe43432b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.domain_events
    ADD CONSTRAINT fk_rails_8afe43432b FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: observation_groups fk_rails_a4d23a4737; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observation_groups
    ADD CONSTRAINT fk_rails_a4d23a4737 FOREIGN KEY (subject_id) REFERENCES public.subjects(id);


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
-- Name: observation_groups fk_rails_caaaf09583; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observation_groups
    ADD CONSTRAINT fk_rails_caaaf09583 FOREIGN KEY (source_id) REFERENCES public.sources(id);


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
-- Name: intervals fk_rails_ffb9e40026; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intervals
    ADD CONSTRAINT fk_rails_ffb9e40026 FOREIGN KEY (source_id) REFERENCES public.sources(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
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

