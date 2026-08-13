CREATE TABLE mailing_list_archive_epochs (
    id                      bigint
                                GENERATED ALWAYS AS IDENTITY
                                PRIMARY KEY,

    mailing_list_id         bigint NOT NULL
                                REFERENCES mailing_lists(id)
                                ON DELETE CASCADE,

    epoch                   integer NOT NULL,

    -- Commit in this epoch's master history that was last processed.
    last_scanned_commit_oid text,

    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT mailing_list_archive_epochs_list_epoch_key
        UNIQUE (mailing_list_id, epoch),

    CONSTRAINT mailing_list_archive_epochs_epoch_check
        CHECK (epoch >= 0)
);

ALTER TABLE mailing_lists
    DROP COLUMN last_scanned_oid;
