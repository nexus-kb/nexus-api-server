CREATE TABLE vapor_queue_jobs (
    id                  text PRIMARY KEY,
    queue_key           text NOT NULL,
    job_name            text NOT NULL,
    payload             bytea NOT NULL,

    max_retry_count     bigint NOT NULL DEFAULT 0,
    attempts            bigint NOT NULL DEFAULT 0,

    delay_until         timestamptz,
    queued_at           timestamptz NOT NULL,

    state               text NOT NULL DEFAULT 'stored',
    lease_expires_at    timestamptz,

    updated_at          timestamptz NOT NULL DEFAULT now(),
    
    CONSTRAINT vapor_queue_jobs_max_retry_count_check
        CHECK (max_retry_count >= 0),

    CONSTRAINT vapor_queue_jobs_attempts_check
        CHECK (attempts >= 0),

    CONSTRAINT vapor_queue_jobs_state_check
        CHECK (state IN ('stored', 'ready', 'processing')),

    CONSTRAINT vapor_queue_jobs_processing_lease_check
        CHECK (
            (state = 'processing' AND lease_expires_at IS NOT NULL)
            OR
            (state <> 'processing' AND lease_expires_at IS NULL)
        )
);

CREATE INDEX vapor_queue_jobs_dequeue_idx
    ON vapor_queue_jobs (
        queue_key,
        state,
        delay_until,
        queued_at,
        id
    );
