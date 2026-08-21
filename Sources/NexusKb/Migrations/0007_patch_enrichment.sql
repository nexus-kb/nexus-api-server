CREATE TABLE enrichment_runs (
    id                  bigint
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    patch_id            bigint NOT NULL
                            REFERENCES patches(id)
                            ON DELETE CASCADE,

    extractor_version   text NOT NULL,

    created_at          timestamptz NOT NULL DEFAULT now(),
    completed_at        timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT enrichment_runs_patch_version_key
        UNIQUE (patch_id, extractor_version),

    CONSTRAINT enrichment_runs_identity_key
        UNIQUE (id, patch_id, extractor_version),

    CONSTRAINT enrichment_runs_extractor_version_check
        CHECK (extractor_version <> '')
);

CREATE INDEX enrichment_runs_version_patch_idx
    ON enrichment_runs(extractor_version, patch_id);

CREATE TABLE patch_diff_files (
    id                  bigint
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    patch_id            bigint NOT NULL
                            REFERENCES patches(id)
                            ON DELETE CASCADE,

    enrichment_run_id   bigint NOT NULL,
    extractor_version   text NOT NULL,
    file_index          integer NOT NULL,

    old_path            text,
    new_path            text,
    operation           text NOT NULL,
    diff_header         text NOT NULL,
    header_lines        text[] NOT NULL,
    trailing_lines      text[] NOT NULL,

    CONSTRAINT patch_diff_files_run_fk
        FOREIGN KEY (
            enrichment_run_id,
            patch_id,
            extractor_version
        ) REFERENCES enrichment_runs (
            id,
            patch_id,
            extractor_version
        ) ON DELETE CASCADE,

    CONSTRAINT patch_diff_files_run_index_key
        UNIQUE (enrichment_run_id, file_index),

    CONSTRAINT patch_diff_files_identity_key
        UNIQUE (
            id,
            patch_id,
            enrichment_run_id,
            extractor_version
        ),

    CONSTRAINT patch_diff_files_file_index_check
        CHECK (file_index >= 0),

    CONSTRAINT patch_diff_files_path_check
        CHECK (old_path IS NOT NULL OR new_path IS NOT NULL),

    CONSTRAINT patch_diff_files_operation_check
        CHECK (
            operation IN (
                'modified',
                'added',
                'deleted',
                'renamed',
                'copied'
            )
        )
);

CREATE INDEX patch_diff_files_patch_version_idx
    ON patch_diff_files(patch_id, extractor_version, file_index);

CREATE TABLE patch_diff_hunks (
    id                  bigint
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    patch_id            bigint NOT NULL
                            REFERENCES patches(id)
                            ON DELETE CASCADE,

    enrichment_run_id   bigint NOT NULL,
    extractor_version   text NOT NULL,
    file_id             bigint NOT NULL,
    hunk_index          integer NOT NULL,

    old_start           integer NOT NULL,
    old_count           integer NOT NULL,
    new_start           integer NOT NULL,
    new_count           integer NOT NULL,
    section_header      text,
    raw_header          text NOT NULL,

    CONSTRAINT patch_diff_hunks_run_fk
        FOREIGN KEY (
            enrichment_run_id,
            patch_id,
            extractor_version
        ) REFERENCES enrichment_runs (
            id,
            patch_id,
            extractor_version
        ) ON DELETE CASCADE,

    CONSTRAINT patch_diff_hunks_file_fk
        FOREIGN KEY (
            file_id,
            patch_id,
            enrichment_run_id,
            extractor_version
        ) REFERENCES patch_diff_files (
            id,
            patch_id,
            enrichment_run_id,
            extractor_version
        ) ON DELETE CASCADE,

    CONSTRAINT patch_diff_hunks_file_index_key
        UNIQUE (file_id, hunk_index),

    CONSTRAINT patch_diff_hunks_identity_key
        UNIQUE (
            id,
            patch_id,
            enrichment_run_id,
            extractor_version,
            file_id
        ),

    CONSTRAINT patch_diff_hunks_hunk_index_check
        CHECK (hunk_index >= 0),

    CONSTRAINT patch_diff_hunks_ranges_check
        CHECK (
            old_start >= 0
            AND old_count >= 0
            AND new_start >= 0
            AND new_count >= 0
        )
);

CREATE INDEX patch_diff_hunks_patch_version_idx
    ON patch_diff_hunks(
        patch_id,
        extractor_version,
        file_id,
        hunk_index
    );

CREATE TABLE patch_symbol_observations (
    id                  bigint
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    patch_id            bigint NOT NULL
                            REFERENCES patches(id)
                            ON DELETE CASCADE,

    enrichment_run_id   bigint NOT NULL,
    extractor_version   text NOT NULL,
    file_id             bigint NOT NULL,
    hunk_id             bigint NOT NULL,

    symbol_name         text NOT NULL,
    symbol_kind         text NOT NULL,
    relationship        text NOT NULL,

    line_index          integer,
    line_kind           text,

    evidence_method     text NOT NULL,
    confidence          double precision NOT NULL,

    CONSTRAINT patch_symbol_observations_run_fk
        FOREIGN KEY (
            enrichment_run_id,
            patch_id,
            extractor_version
        ) REFERENCES enrichment_runs (
            id,
            patch_id,
            extractor_version
        ) ON DELETE CASCADE,

    CONSTRAINT patch_symbol_observations_file_fk
        FOREIGN KEY (
            file_id,
            patch_id,
            enrichment_run_id,
            extractor_version
        ) REFERENCES patch_diff_files (
            id,
            patch_id,
            enrichment_run_id,
            extractor_version
        ) ON DELETE CASCADE,

    CONSTRAINT patch_symbol_observations_hunk_fk
        FOREIGN KEY (
            hunk_id,
            patch_id,
            enrichment_run_id,
            extractor_version,
            file_id
        ) REFERENCES patch_diff_hunks (
            id,
            patch_id,
            enrichment_run_id,
            extractor_version,
            file_id
        ) ON DELETE CASCADE,

    CONSTRAINT patch_symbol_observations_symbol_name_check
        CHECK (symbol_name <> ''),

    CONSTRAINT patch_symbol_observations_symbol_kind_check
        CHECK (symbol_kind IN ('function', 'macro', 'type')),

    CONSTRAINT patch_symbol_observations_relationship_check
        CHECK (
            relationship IN (
                'modifies',
                'adds',
                'deletes',
                'calls',
                'mentions'
            )
        ),

    CONSTRAINT patch_symbol_observations_line_check
        CHECK (
            (
                line_index IS NULL
                AND line_kind IS NULL
            )
            OR (
                line_index >= 0
                AND line_kind IN (
                    'context',
                    'addition',
                    'deletion',
                    'noNewlineMarker'
                )
            )
        ),

    CONSTRAINT patch_symbol_observations_evidence_check
        CHECK (
            evidence_method IN (
                'hunkHeader',
                'walkback',
                'changedLineDefinition',
                'changedLineCall',
                'changedLineMention'
            )
        ),

    CONSTRAINT patch_symbol_observations_confidence_check
        CHECK (confidence >= 0 AND confidence <= 1)
);

CREATE INDEX patch_symbol_observations_patch_version_idx
    ON patch_symbol_observations(
        patch_id,
        extractor_version,
        file_id,
        hunk_id
    );

CREATE INDEX patch_symbol_observations_symbol_idx
    ON patch_symbol_observations(
        symbol_name,
        relationship,
        patch_id
    );
