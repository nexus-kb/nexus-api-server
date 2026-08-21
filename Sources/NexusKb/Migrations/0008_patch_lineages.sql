CREATE TABLE patch_lineages (
    id                  bigint
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    canonical_subject   text NOT NULL,
    first_sent_at       timestamptz,
    latest_sent_at      timestamptz,

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT patch_lineages_subject_check
        CHECK (canonical_subject <> '')
);

CREATE INDEX patch_lineages_latest_idx
    ON patch_lineages(latest_sent_at DESC, id DESC);

CREATE TABLE patchset_lineage_state (
    patchset_id         bigint PRIMARY KEY
                            REFERENCES patchsets(id)
                            ON DELETE CASCADE,

    lineage_id          bigint NOT NULL
                            REFERENCES patch_lineages(id)
                            ON DELETE RESTRICT,

    phase               text NOT NULL,
    revision            integer NOT NULL,
    revision_explicit   boolean NOT NULL,
    is_resend           boolean NOT NULL,

    display_subject     text NOT NULL,
    normalized_subject  text NOT NULL,
    author_email        text NOT NULL,
    change_id           text,
    base_commit         text,

    match_source        text NOT NULL,
    match_confidence    integer NOT NULL,
    match_evidence      jsonb NOT NULL DEFAULT '{}'::jsonb,
    matcher_version     integer NOT NULL,
    manual_lock         boolean NOT NULL DEFAULT false,

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT patchset_lineage_phase_check
        CHECK (phase IN ('RFC', 'PATCH')),

    CONSTRAINT patchset_lineage_revision_check
        CHECK (revision >= 1),

    CONSTRAINT patchset_lineage_subject_check
        CHECK (
            display_subject <> ''
            AND normalized_subject <> ''
        ),

    CONSTRAINT patchset_lineage_author_check
        CHECK (author_email <> ''),

    CONSTRAINT patchset_lineage_source_check
        CHECK (
            match_source IN (
                'singleton',
                'change-id',
                'reply-chain',
                'subject-author',
                'manual'
            )
        ),

    CONSTRAINT patchset_lineage_confidence_check
        CHECK (
            match_confidence >= 0
            AND match_confidence <= 100
        ),

    CONSTRAINT patchset_lineage_matcher_version_check
        CHECK (matcher_version >= 1),

    CONSTRAINT patchset_lineage_manual_source_check
        CHECK (
            NOT manual_lock
            OR match_source = 'manual'
        )
);

CREATE INDEX patchset_lineage_lineage_idx
    ON patchset_lineage_state(
        lineage_id,
        phase,
        revision,
        patchset_id
    );

CREATE INDEX patchset_lineage_change_id_idx
    ON patchset_lineage_state(lower(change_id))
    WHERE change_id IS NOT NULL;

CREATE INDEX patchset_lineage_subject_author_idx
    ON patchset_lineage_state(
        normalized_subject,
        lower(author_email),
        patchset_id
    );

CREATE TABLE patch_lineage_events (
    id                  bigint
                            GENERATED ALWAYS AS IDENTITY
                            PRIMARY KEY,

    patchset_id         bigint NOT NULL
                            REFERENCES patchsets(id)
                            ON DELETE CASCADE,

    previous_lineage_id bigint,
    -- Intentionally not an FK: audit rows retain the historical numeric
    -- lineage identifier after an empty lineage is removed.
    lineage_id          bigint NOT NULL,

    match_source        text NOT NULL,
    match_confidence    integer NOT NULL,
    match_evidence      jsonb NOT NULL DEFAULT '{}'::jsonb,
    matcher_version     integer NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT patch_lineage_events_confidence_check
        CHECK (
            match_confidence >= 0
            AND match_confidence <= 100
        )
);

CREATE INDEX patch_lineage_events_patchset_idx
    ON patch_lineage_events(patchset_id, created_at DESC, id DESC);

CREATE FUNCTION delete_empty_patch_lineage()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM patch_lineages AS lineage
    WHERE lineage.id = OLD.lineage_id
      AND NOT EXISTS (
            SELECT 1
            FROM patchset_lineage_state AS state
            WHERE state.lineage_id = lineage.id
      );

    RETURN NULL;
END;
$$;

CREATE TRIGGER patchset_lineage_delete_empty
AFTER DELETE ON patchset_lineage_state
FOR EACH ROW
EXECUTE FUNCTION delete_empty_patch_lineage();
