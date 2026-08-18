# LKML Database P1 Verification Report

Date: August 18, 2026  
Companions: [Initial-Ingest Profiling Report](lkml-ingest-profiling-report.md),
[P0 10k-Batch Benchmark Report](lkml-ingest-p0-10k-benchmark-report.md), and
[Mail-Parser P0 Verification Report](lkml-mail-parser-p0-verification-report.md)

## Summary

The batched people and recipient implementation, PostgreSQL 18 message UPSERT `OLD` state, and
batch-local message cache achieved their targets. A warning-level Debug Time Profiler run processed
10,000 consecutive LKML epoch-0 commits in approximately 16.4 seconds, or 609.6 messages per
second. Compared with the preceding 10k run, wall time fell 53.0%, SQL calls fell 65.9%, and
PostgreSQL execution time fell 51.2%.

## Results

| Metric | Previous 10k | P1 result | Change |
|---|---:|---:|---:|
| Wall time | 34.887 s | approximately 16.405 s | -53.0% |
| Throughput | 286.6/s | approximately 609.6/s | +112.7% |
| Database-batch wall span | 32.12 s | approximately 12.60 s | -60.8% |
| SQL calls | 127,025 | 43,366 | -65.9% |
| SQL calls per message | 12.703 | 4.337 | -65.9% |
| PostgreSQL execution time | 4.043 s | 1.972 s | -51.2% |
| Existing-message lookups per message | 2.30 | 0.307 | -86.7% |
| Logical WAL | 60.18 MB | 76.96 MB | +27.9% |
| Client-backend WAL fsyncs | not retained | 13 | 0.0013/message |

The run used a different consecutive archive slice, so the WAL change includes message-content
variance and is not an isolated regression measurement.

## People, recipients, and message resolution

The batch contained 24,686 recipient references. One set-based people statement reduced them to
1,628 person modifications: 775 inserts and 853 updates. Recipient persistence used one delete and
one insert statement, producing 24,682 final links.

| Operation | Calls | PostgreSQL execution |
|---|---:|---:|
| Batched people resolution | 1 | 65.9 ms |
| Batched recipient deletion | 1 | 357.1 ms |
| Batched recipient insertion | 1 | 208.8 ms |
| Existing-message lookup | 3,069 | 41.8 ms |

The message cache satisfied approximately 6,931 anchor resolutions. Placeholder inserts returned
their IDs directly, and PostgreSQL 18 `RETURNING old.thread_id` eliminated the separate
target-message lookup.

The recipient delete affected no rows in this slice. A possible follow-up is to return
`old.is_placeholder` from the message UPSERT and omit newly inserted and placeholder-replacement
messages from the delete input.

## Remaining bottleneck

The database batch remains the largest wall-clock phase. Its remaining calls are concentrated in
three per-message statements:

| Statement | Calls | PostgreSQL execution |
|---|---:|---:|
| Message UPSERT | 10,000 | 674.1 ms |
| Mailing-list-link UPSERT | 10,000 | 260.4 ms |
| Thread metadata update | 10,000 | 120.5 ms |

These statements account for 30,000 of 43,366 calls. The next material optimization is the P2
set-based staging pipeline, beginning with mailing-list links and thread metadata.

## CPU profile and validation

The ingest window contained 9.465 seconds of sampled CPU. `IngestMessageParser.parse` used 2.808
seconds, `PostgresIngestService.ingestBatch` used 1.967 seconds, and `persistMessage` used 1.446
seconds. Batched people resolution and recipient replacement used 0.237 and 0.141 seconds,
respectively.

The cursor advanced exactly 10,000 ordered first-parent commits:

```text
345e7953df7a1536e70f5782fb4d5f642f1e7def
    -> f18b4b04fffda47b48c0cf148f87eaba3d2f50b5
```

The starting and final cursors retained the required ancestry, the final cursor remained an
ancestor of epoch master, the queue finished empty, PostgreSQL recorded no rollbacks or temporary
files, and 498,488 commits remained in epoch 0.

`mailing_list_archive_epochs.updated_at` uses `now()`, which records the transaction start rather
than commit time. The duration above therefore comes from the Time Profiler event window, not the
cursor timestamp.

The server and worker were stopped after collection. The temporary Instruments trace and XML
export were deleted because the trace inherited the worker environment.
