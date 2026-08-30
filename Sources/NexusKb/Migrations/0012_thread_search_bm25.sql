-- The thread ID is both the ParadeDB key and the API result identity.
CREATE INDEX thread_search_documents_bm25_idx
ON thread_search_documents
USING paradedb (
    thread_id,
    subject,
    content
)
WITH (key_field = 'thread_id');

ANALYZE thread_search_documents;
