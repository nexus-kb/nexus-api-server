# LKML P0 10k-Batch Benchmark Report

Date: August 18, 2026  
Companion to: [LKML Initial-Ingest Profiling Report](lkml-ingest-profiling-report.md)

## Summary

The new initial-backfill path processed 10,000 LKML commits in 28.96 seconds, or 345.3 commits per
second. Compared with the previous warm 5,000-commit run at 94.9 commits per second, throughput
improved by 3.64 times and wall time per commit fell by 72.5%.

The run used the new default database batch size of 10,000, one generated first-parent revision
manifest, one bounded `git cat-file --batch` operation, one database transaction, and one durable
cursor update.

## Test configuration

- Swift Debug executable with logging at `warning`.
- One Vapor Queues worker.
- PostgreSQL 18.4 with 4 vCPUs and 1 GiB memory.
- LKML mailing-list ID 2, epoch 0.
- Database batch size: 10,000 commits.
- Job work limit: 10,000 commits.
- Warm application, Git, filesystem, and PostgreSQL caches.
- PostgreSQL statement, database, I/O, WAL, and checkpointer counters reset before dispatch.

The cursor advanced exactly 10,000 ordered first-parent commits:

```text
a6327d9136525ea80609ae64107175789c974ea6
    -> fb5240a628a941767cdeab76efb2c62fd9d0960e
```

## Results

| Metric | Previous warm run | New 10k run | Change |
|---|---:|---:|---:|
| Commits | 5,000 | 10,000 | — |
| Database batch size | 500 | 10,000 | 20× larger |
| End-to-end duration | 52.7 s | 28.96 s | — |
| Throughput | 94.9/s | 345.3/s | 3.64× |
| Wall time per commit | 10.54 ms | 2.90 ms | −72.5% |
| SQL calls per commit | 17.81 | 12.88 | −27.7% |
| Transactions per commit | 1.023 | 0.0055 | −99.46% |
| Durable cursor updates | 5,000 | 1 | −99.98% |
| Client WAL fsyncs per commit | 1.011 | 0.0013 | −99.87% |
| Logical WAL per commit | approximately 10.1 KB | 8.81 KB | −12.8% |
| PostgreSQL execution share | 2.6% | 14.5% | Bottleneck shifted toward SQL |

The new path generated one manifest containing 558,488 OIDs. The previous 500-commit continuation
design would have processed an estimated 11,074,760 OID lines for the same 10,000-commit slice and
fixed tip. The new path therefore reduced revision-list output by 94.96%, or 19.8 times.

Peak worker RSS was approximately 220 MiB, and the PostgreSQL container peaked at approximately
341 MiB. The larger atomic batch therefore trades higher memory use for substantially lower Git,
transaction, cursor, and WAL synchronization overhead.

## Validation

- All 34 automated tests passed.
- The final cursor was exactly 10,000 first-parent commits after the starting cursor.
- The starting cursor, final cursor, and fixed target tip retained the required ancestry order.
- The database recorded zero rollbacks, deadlocks, or temporary files.
- The queue job cleared successfully.
- Lease ownership was renewed three times. The periodic 60-second heartbeat was not exercised
  because the complete run finished in less than 29 seconds.

## Analysis

The P0 work removed the archive-side scaling defect and nearly all transaction and cursor overhead.
PostgreSQL execution time rose from 2.6% to 14.5% of wall time because the application-side work
around the database became much cheaper.

Recipient and person persistence is now the clearest next bottleneck. The run issued 27,955 person
upserts and 27,955 recipient-link inserts. Only 1,002 people were inserted, while 26,953 existing
people rows were updated. Together, the person and recipient statements accounted for about 60% of
PostgreSQL execution time.

This was a consecutive 10,000-commit LKML slice rather than a replay of the exact 5,000 commits from
the original report. It is an end-to-end comparison under the same warm Debug environment, not an
isolated microbenchmark. No new Instruments CPU trace was captured.

