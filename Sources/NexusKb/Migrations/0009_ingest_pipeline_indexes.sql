CREATE INDEX patchsets_author_sent_idx
    ON patchsets(author, sent_at, id);

CREATE INDEX patchsets_lineage_backfill_order_idx
    ON patchsets(
        sent_at ASC NULLS FIRST,
        id ASC
    );
