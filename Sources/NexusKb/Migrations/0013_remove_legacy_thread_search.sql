DROP INDEX threads_subject_search_idx;

ALTER TABLE threads
DROP COLUMN subject_search;

ANALYZE threads;
