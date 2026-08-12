-- Mailing lists and archive ingestion state

CREATE TABLE mailing_lists (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                text NOT NULL,
    archive_group       text NOT NULL UNIQUE,
    archive_path        text,
    
    -- Cursor for last scanned message
    last_scanned_oid    text,

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

-- A discussion thread. root_message_id intentionally has no FK:
-- ingestion may discover replies before the root message.
CREATE TABLE threads (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    root_message_id     text NOT NULL,
    subject             text,
    last_updated_at     timestamptz NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT threads_root_message_id_key UNIQUE (root_message_id)
);

-- One parsed RFC email.
CREATE TABLE messages (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    message_id          text NOT NULL UNIQUE,
    thread_id           bigint NOT NULL
                            REFERENCES threads(id) ON DELETE CASCADE,

    in_reply_to         text,
    references_ids      text[] NOT NULL DEFAULT ARRAY[]::text[],

    author              text,
    subject             text,
    sent_at             timestamptz,

    -- Decoded text/plain content, not necessarily the original MIME message.
    body                text NOT NULL DEFAULT '',

    -- Preserve the normalized display strings from the original headers.
    to_recipients       text NOT NULL DEFAULT '',
    cc_recipients       text NOT NULL DEFAULT '',

    -- True for temporary parents created when a reply arrives first.
    is_placeholder      boolean NOT NULL DEFAULT false,

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX messages_thread_date_idx
    ON messages(thread_id, sent_at, id);

CREATE INDEX messages_date_idx
    ON messages(sent_at DESC);

CREATE INDEX messages_in_reply_to_idx
    ON messages(in_reply_to)
    WHERE in_reply_to IS NOT NULL;

-- A message can be present in more than one mailing-list archive.
CREATE TABLE messages_mailing_lists (
    message_id          bigint NOT NULL
                            REFERENCES messages(id) ON DELETE CASCADE,
    mailing_list_id     bigint NOT NULL
                            REFERENCES mailing_lists(id) ON DELETE CASCADE,

    -- Git object containing the message in this particular public-inbox mirror.
    archive_blob_oid    text,

    first_seen_at       timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (message_id, mailing_list_id)
);

CREATE INDEX messages_mailing_lists_list_idx
    ON messages_mailing_lists(mailing_list_id, message_id);

CREATE INDEX messages_mailing_lists_blob_idx
    ON messages_mailing_lists(archive_blob_oid)
    WHERE archive_blob_oid IS NOT NULL;


-- People and message recipients

CREATE TABLE people (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                text,
    email               text NOT NULL,
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- Treat email addresses case-insensitively without requiring citext.
CREATE UNIQUE INDEX people_email_lower_key
    ON people(lower(email));

CREATE TABLE messages_recipients (
    message_id          bigint NOT NULL
                            REFERENCES messages(id) ON DELETE CASCADE,
    person_id           bigint NOT NULL
                            REFERENCES people(id) ON DELETE CASCADE,
    recipient_type      text NOT NULL,

    PRIMARY KEY (message_id, person_id, recipient_type),

    CONSTRAINT messages_recipients_type_check
        CHECK (recipient_type IN ('To', 'Cc'))
);

CREATE INDEX messages_recipients_person_idx
    ON messages_recipients(person_id, message_id);


-- Patch series

CREATE TABLE patchsets (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    thread_id           bigint NOT NULL
                            REFERENCES threads(id) ON DELETE CASCADE,

    cover_letter_message_id text
                            REFERENCES messages(message_id)
                            ON DELETE SET NULL,

    subject             text,
    author              text,
    sent_at             timestamptz,

    -- Ingestion state only; review-related states are intentionally absent.
    status              text NOT NULL DEFAULT 'Incomplete',

    total_parts         integer NOT NULL DEFAULT 1,
    received_parts      integer NOT NULL DEFAULT 0,

    -- Index of the message whose subject was selected for display.
    -- Cover letters normally have index 0.
    subject_index       integer NOT NULL DEFAULT 9999,
    parser_version      integer NOT NULL DEFAULT 0,

    to_recipients       text NOT NULL DEFAULT '',
    cc_recipients       text NOT NULL DEFAULT '',

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT patchsets_status_check
        CHECK (status IN ('Incomplete', 'Complete', 'Malformed')),

    CONSTRAINT patchsets_total_parts_check
        CHECK (total_parts >= 1),

    CONSTRAINT patchsets_received_parts_check
        CHECK (received_parts >= 0),

    CONSTRAINT patchsets_subject_index_check
        CHECK (subject_index >= 0)
);

CREATE INDEX patchsets_thread_idx
    ON patchsets(thread_id);

CREATE INDEX patchsets_status_date_idx
    ON patchsets(status, sent_at DESC);

CREATE INDEX patchsets_cover_message_idx
    ON patchsets(cover_letter_message_id)
    WHERE cover_letter_message_id IS NOT NULL;

-- One actual diff-bearing message in a patch series.
CREATE TABLE patches (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patchset_id         bigint NOT NULL
                            REFERENCES patchsets(id) ON DELETE CASCADE,

    message_id          text NOT NULL UNIQUE
                            REFERENCES messages(message_id) ON DELETE CASCADE,

    part_index          integer NOT NULL,
    diff                text NOT NULL,

    created_at          timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT patches_part_index_check
        CHECK (part_index >= 1),

    -- Prevent two distinct patches from occupying the same series position.
    CONSTRAINT patches_patchset_part_key
        UNIQUE (patchset_id, part_index)
);

CREATE INDEX patches_patchset_idx
    ON patches(patchset_id, part_index);


-- Subsystem classification

CREATE TABLE subsystems (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name                text NOT NULL UNIQUE,
    mailing_list_address text UNIQUE
);

CREATE TABLE messages_subsystems (
    message_id          bigint NOT NULL
                            REFERENCES messages(id) ON DELETE CASCADE,
    subsystem_id        bigint NOT NULL
                            REFERENCES subsystems(id) ON DELETE CASCADE,

    PRIMARY KEY (message_id, subsystem_id)
);

CREATE TABLE threads_subsystems (
    thread_id           bigint NOT NULL
                            REFERENCES threads(id) ON DELETE CASCADE,
    subsystem_id        bigint NOT NULL
                            REFERENCES subsystems(id) ON DELETE CASCADE,

    PRIMARY KEY (thread_id, subsystem_id)
);

CREATE TABLE patchsets_subsystems (
    patchset_id         bigint NOT NULL
                            REFERENCES patchsets(id) ON DELETE CASCADE,
    subsystem_id        bigint NOT NULL
                            REFERENCES subsystems(id) ON DELETE CASCADE,

    PRIMARY KEY (patchset_id, subsystem_id)
);

CREATE TABLE patches_subsystems (
    patch_id            bigint NOT NULL
                            REFERENCES patches(id) ON DELETE CASCADE,
    subsystem_id        bigint NOT NULL
                            REFERENCES subsystems(id) ON DELETE CASCADE,

    PRIMARY KEY (patch_id, subsystem_id)
);

CREATE INDEX messages_subsystems_subsystem_idx
    ON messages_subsystems(subsystem_id, message_id);

CREATE INDEX threads_subsystems_subsystem_idx
    ON threads_subsystems(subsystem_id, thread_id);

CREATE INDEX patchsets_subsystems_subsystem_idx
    ON patchsets_subsystems(subsystem_id, patchset_id);

CREATE INDEX patches_subsystems_subsystem_idx
    ON patches_subsystems(subsystem_id, patch_id);
