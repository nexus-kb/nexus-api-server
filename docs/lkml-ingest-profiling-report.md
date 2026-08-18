# LKML Initial-Ingest Profiling Report

Date: August 18, 2026  
Repository: Nexus-KB  
Workload: Linux Kernel Mailing List public-inbox epoch ingestion

## Executive summary

The measured ingest path is primarily limited by application-side archive traversal, mail parsing,
and per-message database protocol overhead. PostgreSQL query execution is not currently the main
bottleneck.

The larger measured run ingested 5,000 LKML commits in 52.7 seconds, or approximately 95 commits
per second. It issued 89,039 SQL statements, opened approximately 5,000 transactions, and generated
50.5 MB of logical WAL. PostgreSQL spent only 1.39 seconds executing those statements, approximately
2.6% of the end-to-end wall time.

Xcode Time Profiler attributed the largest inclusive CPU shares to:

1. Mail parsing: 36.9%.
2. Git archive traversal and commit-list materialization: 27.5%.
3. PostgresNIO, PostgreSQL protocol handling, and connection-pool work: 27.4%.
4. Nexus-KB ingest-service logic: 8.0%.

The highest-priority changes are to stop regenerating and materializing the complete remaining Git
history for every 500-message job, replace the mail header/body delimiter implementation with a
single bounded scan, and move transaction and cursor handling from message scope to batch scope.

## Scope

This investigation covered the existing initial-ingest path implemented in:

- `Sources/NexusKb/Jobs/PublicInboxIngestJobs.swift`
- `Sources/NexusKb/Ingest/PublicInboxArchive.swift`
- `Sources/NexusKb/Ingest/PostgresIngestService.swift`
- `Sources/NexusKb/Ingest/PostgresPatchIngestService.swift`
- `Sources/MailParser/`
- `Sources/NexusKb/Queues/PostgresQueuesDriver.swift`

It measured the existing implementation without changing application source code, schema, or
indexes. The profiling runs advanced the real LKML epoch-0 cursor by a total of 6,000 commits.

## Test environment

### Application

- Swift 6 Nexus-KB executable.
- Vapor 4.
- PostgresNIO 1.33.1.
- Vapor Queues with the custom PostgreSQL queue driver.
- Queue worker count: 1.
- Ingest batch size: 500 commits.
- Logging level during measured runs: `warning`.
- Executable configuration: Debug.

The Debug configuration matters for absolute CPU costs, particularly Swift generic-metadata,
allocation, and bounds-checking overhead. The identified full-history scan, repeated data copies,
query amplification, transaction count, WAL volume, and table churn are architectural observations
and are not artifacts of the build configuration.

### PostgreSQL

- PostgreSQL 18.4, Debian image `postgres:18`, arm64.
- Apple `container` CLI 1.2.2.
- Container name: `postgres18`.
- Resources: 4 vCPUs and 1 GiB memory.
- Host port: 5432.
- Data stored through the existing bind mount at `/Users/tansanrao/work/postgres-data`.
- Database: `nexus`.

At the start of the session, the database contained approximately:

| Relation | Approximate rows | Total relation size |
|---|---:|---:|
| `messages` | 200,748 | 689 MB |
| `messages_recipients` | 2,990,552 | 378 MB |
| `patches` | 65,967 | 214 MB |
| `messages_mailing_lists` | 185,035 | 48 MB |
| `patchsets` | 23,111 | 25 MB |
| `threads` | 26,400 | 11 MB |
| `people` | 8,045 | 1.5 MB |

The row values above came from PostgreSQL planner estimates in `pg_class.reltuples`; they are not
exact counts.

### LKML archive

The archive was read from:

```text
/Users/tansanrao/work/lore-mirrors/lkml
```

It contains 20 public-inbox Git epochs with 6,438,512 first-parent commits in total. Individual
epochs contain approximately 204,000 to 570,000 commits.

## PostgreSQL statistics configuration

The existing PostgreSQL cluster was configured with:

```text
shared_preload_libraries = pg_stat_statements
compute_query_id = on
track_io_timing = on
track_wal_io_timing = on
track_activity_query_size = 4096
```

The `pg_stat_statements` 1.12 extension was installed in the `nexus` database. Its default
`pg_stat_statements.save = on` setting keeps statement statistics across an orderly PostgreSQL
shutdown.

The server was restarted after setting `shared_preload_libraries`, and all settings were verified
through `pg_settings` before profiling.

## Measurement procedure

### PostgreSQL counters

Immediately before each bounded run, the following statistics were reset:

```sql
SELECT pg_stat_statements_reset();
SELECT pg_stat_reset();
SELECT pg_stat_reset_shared('wal');
SELECT pg_stat_reset_shared('io');
SELECT pg_stat_reset_shared('checkpointer');
```

The start timestamp, WAL position, queue state, and archive cursor were recorded. After the queue
became empty, the following sources were collected:

- `pg_stat_statements`
- `pg_stat_user_tables`
- `pg_stat_user_indexes`
- `pg_stat_database`
- `pg_stat_io`
- `pg_stat_wal`
- `pg_stat_checkpointer`
- `mailing_list_archive_epochs`
- `vapor_queue_jobs`

The statistics include a small number of queue-control and measurement queries in addition to the
ingest statements. Their contribution is negligible compared with the 89,039 total statement calls
in the 5,000-commit run.

### Wall-clock throughput

The first run queued 1,000 commits as two 500-commit jobs. Its duration was measured from queue
worker start until the epoch cursor's final `updated_at` value.

The second run queued 5,000 commits as ten 500-commit jobs. Its duration was measured from the HTTP
dispatch timestamp until the epoch cursor's final `updated_at` value.

The dispatch body for the larger run was equivalent to:

```json
{
  "mailingListID": 2,
  "epoch": 0,
  "batchSize": 500,
  "runMessageLimitPerEpoch": 5000
}
```

### CPU profiling

The 5,000-commit queue worker was profiled with Xcode Time Profiler for 60 seconds. The profiler was
attached before dispatch, so the trace covered the complete ingest plus brief idle periods before
and after it.

The symbolicated `time-profile` table was exported from the Instruments trace and aggregated by:

- Leaf symbol.
- Inclusive symbol.
- Nexus-KB and MailParser source path.
- Five-second time bucket.
- Functional category: Git archive, mail parsing, normalization, ingest service, PostgreSQL driver,
  and queue driver.

The trace bundle and exported XML were deleted after aggregation because Instruments includes the
target process environment in trace metadata.

## Throughput results

| Run | Commits | Batch jobs | Duration | Throughput |
|---|---:|---:|---:|---:|
| Baseline | 1,000 | 2 | 14.1 s | 70.9 commits/s |
| Profiled run | 5,000 | 10 | 52.7 s | 94.9 commits/s |

The second run benefited from warm application, filesystem, PostgreSQL, and Git caches. It should
therefore be treated as a warm-cache throughput measurement rather than a cold-start result.

At 94.9 commits per second, ingesting the entire 6.44-million-commit LKML archive would take about
18.8 hours if throughput remained constant. That extrapolation is not a forecast: repeated Git
enumeration becomes cheaper as each epoch's cursor advances, while PostgreSQL tables and indexes
grow throughout the load, and this run used warm caches and a Debug executable.

## CPU profile results

Time Profiler captured 33.9 seconds of aggregate on-CPU samples during its 60-second window.

### Functional categories

Category percentages are inclusive: a stack contributes to a category when it contains a matching
frame.

| Category | CPU time | Inclusive share |
|---|---:|---:|
| Mail parsing | 12.51 s | 36.9% |
| Git archive | 9.32 s | 27.5% |
| PostgreSQL driver/protocol/pool | 9.29 s | 27.4% |
| Ingest service | 2.71 s | 8.0% |
| Text normalization | 0.12 s | 0.35% |
| Queue driver | 0.01 s | 0.04% |

### Important inclusive source frames

| Source frame | CPU time | Inclusive share |
|---|---:|---:|
| `IngestPublicInboxEpochJob` preparation closure | 21.89 s | 64.6% |
| `IngestMessageParser.parse` | 12.51 s | 36.9% |
| `RFCMessageParser.parse` | 12.06 s | 35.6% |
| `PublicInboxEpochRepository.commitOIDs` | 9.29 s | 27.4% |
| `MessageSyntax.parseEntity` | 9.20 s | 27.1% |
| `MessageSyntax.splitHeaderAndBody` | 9.00 s | 26.6% |
| `MessageSyntax.firstIndex` | 8.92 s | 26.3% |
| `PostgresIngestService.ingest` | 2.70 s | 8.0% |
| `MailDateParser.parse` | 2.45 s | 7.2% |
| `PostgresIngestService.persistMessage` | 1.85 s | 5.5% |
| `GitProcess.run` | 1.28 s | 3.8% |
| `MIMEBodyDecoder.decodeTextBodies` | 0.92 s | 2.7% |
| `PostgresIngestService.replaceRecipients` | 0.86 s | 2.5% |

The profile did not attach to child Git processes, so Git's own CPU consumption is not represented.
The Git archive category measures Nexus-KB's work and wait-visible stack activity around Git,
including processing the command output.

## Git archive bottleneck

Each `IngestPublicInboxEpochJob` currently does the following:

1. Runs `git rev-list --reverse --first-parent` from the current cursor through the fixed tip.
2. Reads the complete command output into a `String`.
3. Splits and materializes every remaining OID into `[String]`.
4. Takes only the first 500 entries.
5. Repeats the complete operation in the next job.

For all LKML epochs, the current 500-commit job structure requires 12,888 jobs. Summing the
remaining history length at each job boundary gives an estimated 2.28 billion OID lines processed
over a full initial ingest. At 41 bytes per OID line, that is roughly 93 GB of textual OID output
handled by Nexus-KB, excluding object and collection overhead.

Adding `--max-count=501` to the existing `--reverse` invocation is not correct. It was tested against
the LKML repository and returned the newest 501 commits in reverse order rather than the first 501
commits following the cursor.

## Mail parser bottlenecks

### Header/body delimiter search

`MessageSyntax.splitHeaderAndBody` currently:

1. Copies the complete `Data` value into `[UInt8]`.
2. Scans the full array for CRLFCRLF.
3. Scans it again for LFLF.
4. Scans it again for CRCR.
5. Copies the selected header and body ranges back into separate `Data` values.

For diff-bearing messages, the body can be much larger than the headers even though the delimiter
is normally near the beginning. This implementation accounted for 26.3% of sampled CPU.

### Date parsing

`MailDateParser.parse` constructs and configures a new `DateFormatter` for each candidate format.
There are eight formats, and both `Date` and `Received` headers may be parsed for one message.
Date parsing accounted for 7.2% of sampled CPU.

## PostgreSQL results

### Aggregate database activity

| Metric | 5,000-commit result |
|---|---:|
| Statement calls | 89,039 |
| Calls per commit | 17.8 |
| Total PostgreSQL statement execution time | 1.387 s |
| Statement execution as share of wall time | 2.6% |
| Committed transactions | 5,114 |
| Rolled-back transactions | 0 |
| Shared blocks read | 1,949 |
| Shared block hits | 1,007,279 |
| Approximate buffer hit ratio | 99.8% |
| Database block read time | 201.9 ms |
| Database block write time | 167.6 ms |
| Temporary files | 0 |
| Deadlocks | 0 |

The transaction count includes queue and measurement activity, but it is dominated by the 5,000
per-message ingest transactions.

### WAL and physical I/O

| Metric | 5,000-commit result | Per commit |
|---|---:|---:|
| Logical WAL bytes (`pg_stat_wal`) | 50.5 MB | 10.1 KB |
| Client-backend WAL bytes written | 91.8 MB | 18.4 KB |
| Client-backend WAL writes | 5,065 | 1.01 |
| Client-backend WAL write time | 751.6 ms | 0.15 ms |
| Client-backend WAL fsyncs | 5,057 | 1.01 |
| Client-backend WAL fsync time | 319.9 ms | 0.06 ms |
| Client relation bytes read | 15.9 MB | 3.2 KB |
| Client relation read time | 202.7 ms | 0.04 ms |
| Relation bytes extended | 17.0 MB | 3.4 KB |
| Relation extend time | 168.6 ms | 0.03 ms |

WAL sync time is measurable but is not the present wall-time bottleneck. The high fsync count is
nevertheless a direct consequence of committing once per message and will become more important
after the larger CPU and protocol costs are removed.

### Highest-cost SQL statements

| Statement | Calls | Total execution | Mean execution |
|---|---:|---:|---:|
| Message upsert | 5,000 | 354.0 ms | 0.071 ms |
| Recipient-link insert | 13,375 | 269.6 ms | 0.020 ms |
| Mailing-list-link upsert | 5,000 | 234.8 ms | 0.047 ms |
| Person upsert | 13,375 | 129.5 ms | 0.010 ms |
| Existing-message lookup | 11,522 | 82.1 ms | 0.007 ms |
| Thread metadata update | 5,000 | 56.4 ms | 0.011 ms |
| Patch insert | 300 | 43.8 ms | 0.146 ms |
| Placeholder message insert | 1,522 | 35.1 ms | 0.023 ms |
| Cursor update | 5,000 | 34.6 ms | 0.007 ms |
| Thread insert/upsert | 1,522 | 29.9 ms | 0.020 ms |

None of these statements is individually slow. The problem is the number of protocol round trips
and awaited operations.

### Repeated transaction and cursor statements

The 5,000-commit run executed approximately:

| Operation | Calls |
|---|---:|
| `BEGIN` | 5,010 |
| `COMMIT` | 5,010 |
| Ensure epoch with `INSERT ... ON CONFLICT DO NOTHING` | 5,010 |
| Lock and load epoch cursor | 5,010 |
| Update epoch cursor | 5,000 |

These operations should be batch-scoped rather than message-scoped.

### Table churn

| Relation | Inserts | Updates | Deletes |
|---|---:|---:|---:|
| `messages_recipients` | 13,375 | 0 | 0 |
| `people` | 506 | 12,869 | 0 |
| `messages` | 5,080 | 1,461 | 0 |
| `threads` | 1,522 | 5,000 | 7 |
| `messages_mailing_lists` | 5,000 | 0 | 0 |
| `patchsets` | 363 | 363 | 0 |
| `patches` | 300 | 0 | 0 |
| `mailing_list_archive_epochs` | 0 | 5,000 | 0 |

The 13,375 recipient links referenced only 901 distinct people. The person UPSERT therefore updated
an existing row 12,869 times while inserting only 506 rows. A batch-local people cache or set-based
upsert can eliminate most of this work.

## Prioritized next steps

### P0: replace repeated full-history enumeration

Implement a dedicated initial-backfill execution path that opens one ordered first-parent revision
stream per epoch and consumes it incrementally:

```text
ordered rev-list stream
    -> next bounded OID batch
    -> git cat-file --batch
    -> parse
    -> database batch transaction
    -> durable cursor checkpoint
    -> next OID batch
```

Recommended details:

- Keep the Git revision process or a generated manifest alive across database batches.
- On process restart, regenerate and skip to the durable cursor once; do not regenerate it per batch.
- Preserve oldest-to-newest commit order.
- Keep `cat-file --batch` bounded to the current database batch.
- Separate the database transaction batch size from the queue job's total work limit.
- If this remains a Vapor Queues job, add lease heartbeats or extend the lease safely. A complete epoch
  can take far longer than the current 300-second visibility timeout.

Expected effect: eliminate the estimated 2.28-billion-line repeated OID workload and the largest
archive-side scaling defect.

### P0: replace the mail header/body splitter

Rewrite `MessageSyntax.splitHeaderAndBody` to:

- Use `Data.withUnsafeBytes` or direct `Data` indices.
- Scan once for all three accepted separator patterns.
- Stop at the first separator.
- Avoid converting the complete message to `[UInt8]`.
- Avoid copying the complete body merely to locate a delimiter in the first header block.

Expected effect: remove most of the source path responsible for 26.3% of sampled CPU.

### P0: reuse mail date parsers

Construct the supported date parsers once per `IngestMessageParser` or parsing worker rather than
once per format attempt and message header. Keep parser ownership local to one worker if using
`DateFormatter` to avoid shared mutable formatter state.

Expected effect: reduce the path responsible for 7.2% of sampled CPU.

### P1: use one transaction and one cursor update per database batch

Add an `ingestBatch` operation with these semantics:

1. Open one transaction for the ordered batch.
2. Ensure the archive epoch once.
3. Lock and validate the cursor once.
4. Persist messages in commit order on the same connection.
5. Advance the cursor once to the final commit.
6. Commit the complete batch atomically.

For a 500-message batch this removes approximately 499 transaction commits, epoch checks, cursor
locks, and cursor updates. For the measured 5,000 commits it would reduce about 5,000 transactions
to 10.

Expected effect: lower WAL fsync count, connection-pool work, protocol messages, and Swift async
continuation overhead while providing straightforward all-or-nothing batch retries.

### P1: batch people and recipients

Before persisting recipient links for a batch:

1. Normalize and deduplicate recipient email addresses across the batch.
2. Resolve existing people with one set-based query.
3. Insert or update each distinct person once.
4. Build an in-memory email-to-person-ID map.
5. Insert recipient links with `COPY`, `UNNEST`, or another set-based operation.
6. Delete old recipient links only for messages that are actually being reprocessed.

The measured batch had 13,375 recipient references but only 901 distinct people, so this can reduce
person-resolution calls by approximately 93% for a similar workload.

### P1: reduce existing-message lookups

The measured run made 11,522 `messages.message_id` lookups for 5,000 commits. Review the repeated
lookups in thread resolution, target-message merge handling, and placeholder resolution. Return
enough state from earlier operations to avoid querying the same message again in one transaction.

PostgreSQL 18's richer `RETURNING` capabilities may also allow an UPSERT to return old and new
thread state without a separate pre-update lookup. Any change here must preserve the existing
thread-merge and placeholder semantics.

### P2: introduce a set-based staging pipeline

After the P0 and P1 changes are measured, introduce temporary or unlogged staging tables for each
parsed batch:

1. `COPY` normalized messages and associations into staging.
2. Resolve and merge people set-wise.
3. Resolve thread anchors while preserving commit order.
4. Merge messages, mailing-list links, recipients, patchsets, and patches.
5. Advance the durable archive cursor in the same transaction.

This is the path to reducing statement count from approximately 18 calls per message to a bounded
number of statements per batch.

### P2: add bounded parsing concurrency

Mail parsing is currently sequential within each prepared batch. After removing the delimiter scan
and formatter-construction costs, measure parsing again. If it remains material, parse messages with
a bounded task group while retaining their original commit indexes and restoring order before
database persistence.

Do not increase database-writer concurrency first. Thread merges, placeholder replacement,
patch-series matching, and shared people upserts create more correctness and contention risk than
independent parsing.

### P3: consider initial-load database modes only after remeasurement

Potential later options include:

- Deferring read-only secondary indexes during an offline full backfill.
- Using `synchronous_commit = off` for a reproducible archive-loading session.
- Increasing PostgreSQL memory after measuring cache misses under the optimized ingest path.
- Running independent epochs concurrently only after validating ordering and merge behavior.

These are lower priority because the measured buffer hit ratio was 99.8%, SQL execution consumed
only 2.6% of wall time, and WAL synchronization consumed only a small fraction of the current run.

## Recommended validation sequence

Rerun the same 5,000-commit workload after each group of changes, ideally against a restorable
database snapshot and in both Debug and Release configurations.

1. Git revision stream or manifest.
2. One-pass mail delimiter search and reusable date parsers.
3. Batch transaction and cursor checkpoint.
4. Batched people and recipients.
5. Set-based staging pipeline.
6. Bounded parsing concurrency.

For each run, retain the same measurements:

- End-to-end commits per second.
- CPU time and inclusive source frames.
- Statements per commit.
- Transactions and WAL fsyncs per commit.
- Logical and physical WAL bytes per commit.
- Relation inserts, updates, deletes, and dead tuples.
- PostgreSQL execution time as a fraction of wall time.
- Peak application and PostgreSQL memory.

Initial targets for the next iteration are:

- No full remaining-history materialization at a 500-message boundary.
- One transaction and one cursor update per database batch.
- Fewer than 10 SQL calls per message before staging, then a bounded number per batch with staging.
- Person upserts close to the number of distinct people rather than recipient links.
- Mail delimiter search below 5% of sampled CPU.
- No loss of commit ordering, restartability, idempotency, placeholder resolution, or thread merging.

## Repository and runtime state after profiling

- Application source and schema files were unchanged by the profiling session; this report is the
  only repository file added afterward.
- The profiling runs advanced LKML mailing-list ID 2, epoch 0, by 6,000 commits.
- The final measured cursor was `a6327d9136525ea80609ae64107175789c974ea6`.
- Nexus-KB server and queue-worker processes were stopped after measurement.
- The `postgres18` container was left running with statistics collection enabled.
- Temporary Instruments trace bundles and exported XML files were removed.
