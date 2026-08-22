CREATE TABLE maintenance_runs (
    id                  uuid PRIMARY KEY,
    sequence            bigint GENERATED ALWAYS AS IDENTITY UNIQUE,
    kind                text NOT NULL,
    trigger             text NOT NULL,
    state               text NOT NULL DEFAULT 'queued',
    active_queue_job_id text,
    error               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    started_at          timestamptz,
    finished_at         timestamptz,

    CONSTRAINT maintenance_runs_kind_check
        CHECK (kind IN ('ingest', 'patchLineage', 'grokmirror')),
    CONSTRAINT maintenance_runs_trigger_check
        CHECK (trigger IN ('operator', 'grokmirror')),
    CONSTRAINT maintenance_runs_state_check
        CHECK (state IN ('queued', 'running', 'succeeded', 'failed'))
);

CREATE INDEX maintenance_runs_recent_idx
    ON maintenance_runs(created_at DESC, sequence DESC);

CREATE TABLE maintenance_run_stages (
    id                  uuid PRIMARY KEY,
    run_id              uuid NOT NULL
                            REFERENCES maintenance_runs(id)
                            ON DELETE CASCADE,
    mailing_list_id     bigint NOT NULL
                            REFERENCES mailing_lists(id)
                            ON DELETE RESTRICT,
    position            integer NOT NULL,
    operation           text NOT NULL,
    mode                text NOT NULL,
    state               text NOT NULL DEFAULT 'queued',
    processed_items     bigint NOT NULL DEFAULT 0,
    total_items         bigint,
    current_epoch       integer,
    reset_completed     boolean NOT NULL DEFAULT false,
    error               text,
    started_at          timestamptz,
    finished_at         timestamptz,

    CONSTRAINT maintenance_run_stages_position_check
        CHECK (position >= 0),
    CONSTRAINT maintenance_run_stages_operation_check
        CHECK (operation IN ('ingest', 'patchLineage')),
    CONSTRAINT maintenance_run_stages_mode_check
        CHECK (mode IN ('full', 'incremental')),
    CONSTRAINT maintenance_run_stages_state_check
        CHECK (state IN ('queued', 'running', 'succeeded', 'failed', 'cancelled')),
    CONSTRAINT maintenance_run_stages_processed_check
        CHECK (processed_items >= 0),
    CONSTRAINT maintenance_run_stages_total_check
        CHECK (total_items IS NULL OR total_items >= 0),
    CONSTRAINT maintenance_run_stages_run_position_key
        UNIQUE (run_id, position)
);

CREATE INDEX maintenance_run_stages_run_idx
    ON maintenance_run_stages(run_id, position);

CREATE INDEX maintenance_run_stages_list_state_idx
    ON maintenance_run_stages(mailing_list_id, state, run_id);

CREATE TABLE maintenance_stage_epoch_targets (
    stage_id            uuid NOT NULL
                            REFERENCES maintenance_run_stages(id)
                            ON DELETE CASCADE,
    epoch               integer NOT NULL,
    repository_path     text NOT NULL,
    target_tip_oid      text NOT NULL,
    processed_items     bigint NOT NULL DEFAULT 0,
    completed           boolean NOT NULL DEFAULT false,

    PRIMARY KEY (stage_id, epoch),

    CONSTRAINT maintenance_epoch_targets_epoch_check
        CHECK (epoch >= 0),
    CONSTRAINT maintenance_epoch_targets_processed_check
        CHECK (processed_items >= 0)
);

CREATE TABLE maintenance_stage_patchset_targets (
    stage_id            uuid NOT NULL
                            REFERENCES maintenance_run_stages(id)
                            ON DELETE CASCADE,
    patchset_id         bigint NOT NULL
                            REFERENCES patchsets(id)
                            ON DELETE CASCADE,
    position            bigint NOT NULL,
    force_rematch       boolean NOT NULL,
    processed           boolean NOT NULL DEFAULT false,

    PRIMARY KEY (stage_id, patchset_id),
    CONSTRAINT maintenance_patchset_targets_position_key
        UNIQUE (stage_id, position),
    CONSTRAINT maintenance_patchset_targets_position_check
        CHECK (position >= 0)
);

CREATE INDEX maintenance_patchset_targets_pending_idx
    ON maintenance_stage_patchset_targets(stage_id, processed, position);

CREATE TABLE patch_lineage_work_items (
    mailing_list_id     bigint NOT NULL
                            REFERENCES mailing_lists(id)
                            ON DELETE CASCADE,
    patchset_id         bigint NOT NULL
                            REFERENCES patchsets(id)
                            ON DELETE CASCADE,
    queued_at           timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (mailing_list_id, patchset_id)
);

CREATE INDEX patch_lineage_work_items_list_idx
    ON patch_lineage_work_items(mailing_list_id, queued_at, patchset_id);
