# LKML Database P2 Verification Report

Date: August 18, 2026  
Companions: [P1 Verification Report](lkml-ingest-p1-verification-report.md),
[P0 10k-Batch Benchmark Report](lkml-ingest-p0-10k-benchmark-report.md), and
[Initial-Ingest Profiling Report](lkml-ingest-profiling-report.md)

## Summary

The first P2 set-based change achieved its direct target. Mailing-list-link UPSERTs and thread
metadata updates fell from 20,000 statements to two statements per 10,000-message batch. Total SQL
calls fell 49.2%, from 43,366 to 22,008.

The consecutive warning-level Debug Time Profiler run completed in approximately 21.1 seconds, or
474.6 messages per second. This was slower than P1 because the unchanged message UPSERT and its
surrounding persistence path performed materially more database and CPU work on this archive slice.
The result is a cross-slice measurement, not an isolated regression attributable to the new batch
statements.

## Results

| Metric | P1 | P2 result | Change |
|---|---:|---:|---:|
| Wall span | approximately 16.405 s | approximately 21.071 s | +28.4% |
| Throughput | 609.6/s | 474.6/s | -22.2% |
| Database-batch wall span | approximately 12.60 s | approximately 17.462 s | +38.6% |
| SQL calls | 43,366 | 22,008 | -49.2% |
| SQL calls per message | 4.337 | 2.201 | -49.2% |
| PostgreSQL execution time | 1.972 s | 3.053 s | +54.8% |
| Sampled CPU in the ingest window | 9.465 s | 11.998 s | +26.8% |
| Logical WAL | 76.96 MB | 74.63 MB | -3.0% |
| Client-backend WAL fsyncs | 13 | 14 | effectively unchanged |

## Set-based statement results

| Statement | P1 calls / execution | P2 calls / execution |
|---|---:|---:|
| Mailing-list links | 10,000 / 260.4 ms | 1 / 225.4 ms |
| Thread metadata | 10,000 / 120.5 ms | 1 / 38.6 ms |
| Combined | 20,000 / 380.9 ms | 2 / 264.0 ms |

The two statements eliminated 19,998 database round trips and reduced their combined PostgreSQL
execution time by 30.7%. Thread metadata was updated once for each of 2,695 final threads instead of
once per message.

## Remaining bottleneck

The message UPSERT remained at 10,000 calls and increased from 674.1 ms in P1 to 1,640.2 ms in this
run. It accounted for 89% of the increase in total PostgreSQL execution time. The run also recorded
30.4 MB of relation extension, 674 ms of relation-extension time, and 2,271 full-WAL-buffer events.

This was write and WAL pressure rather than memory exhaustion. The 1 GiB PostgreSQL container
peaked at 708 MB and recorded no memory-pressure, reclaim, swap, OOM, or OOM-kill events. The 31 MB
Message-ID index retained a 99.82% hit rate. The message table grew only 3.8% during the batch, so
relation size and lookup scaling do not explain the 2.43-times increase in mean UPSERT execution.

The next ingest optimization should therefore target the sequential message UPSERT and its
thread/placeholder resolution path. A separate configuration experiment may evaluate larger WAL
buffers, but it should not replace the architectural work.

## Validation

The cursor advanced exactly 10,000 ordered first-parent commits:

```text
f18b4b04fffda47b48c0cf148f87eaba3d2f50b5
    -> 0363b7f397993fe3801c77ead7c82df4334d36fe
```

The starting and final cursors retained the required ancestry, the final cursor remained an
ancestor of the fixed epoch master, and 488,488 commits remained in epoch 0. The queue finished
empty. PostgreSQL recorded no rollbacks, deadlocks, temporary files, or checkpoints during the
measured run.

The server and worker were stopped after collection. The temporary Instruments trace and XML
export were deleted because the trace inherited the worker environment.
