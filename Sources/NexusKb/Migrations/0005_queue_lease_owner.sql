ALTER TABLE vapor_queue_jobs
    ADD COLUMN lease_owner uuid;

CREATE INDEX vapor_queue_jobs_processing_owner_idx
    ON vapor_queue_jobs (
        id,
        lease_owner
    )
    WHERE state = 'processing';
