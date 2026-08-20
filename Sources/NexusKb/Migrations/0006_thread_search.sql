ALTER TABLE threads
ADD COLUMN subject_search tsvector
GENERATED ALWAYS AS (
    to_tsvector(
        'simple',
        COALESCE(subject, '')
    )
) STORED;

CREATE INDEX threads_subject_search_idx
ON threads
USING GIN (subject_search);

ALTER TABLE messages
ADD COLUMN author_search tsvector
GENERATED ALWAYS AS (
    to_tsvector(
        'simple',
        COALESCE(author, '')
    )
) STORED;

CREATE INDEX messages_author_search_idx
ON messages
USING GIN (author_search)
WHERE NOT is_placeholder;

ANALYZE threads (subject_search);
ANALYZE messages (author_search);
