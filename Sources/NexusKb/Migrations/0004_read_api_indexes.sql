CREATE INDEX threads_last_updated_root_idx
    ON threads (
        last_updated_at DESC,
        root_message_id DESC
    );

CREATE INDEX messages_thread_sort_idx
    ON messages (
        thread_id,
        (COALESCE(sent_at, created_at)),
        message_id
    );
