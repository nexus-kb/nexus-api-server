# LKML Mail-Parser P0 Verification Report

Date: August 18, 2026  
Companions: [Initial-Ingest Profiling Report](lkml-ingest-profiling-report.md) and
[P0 10k-Batch Benchmark Report](lkml-ingest-p0-10k-benchmark-report.md)

## Summary

The header/body splitter and date-parser reuse changes removed the targeted CPU bottlenecks. In a
warning-level Debug Time Profiler run over 10,000 messages, `splitHeaderAndBody` fell from 26.6% to
0.46% of sampled CPU, `firstIndex` disappeared, and `IngestMessageParser.parse` fell from 36.9% to
14.2%. Normalized per message, the splitter used 99.5% less sampled CPU and date parsing used 82.4%
less.

The consecutive warm 10,000-message benchmark completed in 34.887 seconds, or 286.6 messages per
second. This was 17.0% slower than the prior 345.3-per-second 10k slice despite the parser gains.
Profiling shows why: parsing all 10,000 messages spanned approximately 2.77 seconds, while
`ingestBatch` occupied approximately 32.12 seconds. Persistence and PostgreSQL protocol volume are
now the dominant limit.

## CPU profile

The corrected trace used a Debug executable, `LOG_LEVEL=warning`, one queue worker, a 10,000-message
database batch, and a 10,000-message job limit. Its ingest window contained 19.49 seconds of sampled
CPU over 36.07 seconds of wall time.

| Inclusive frame | Original 5k profile | New 10k profile | Per-message reduction |
|---|---:|---:|---:|
| `MessageSyntax.splitHeaderAndBody` | 9.00 s / 26.6% | 0.089 s / 0.46% | 99.5% |
| `MessageSyntax.firstIndex` | 8.92 s / 26.3% | absent | eliminated |
| `MessageSyntax.parseEntity` | 9.20 s / 27.1% | 0.382 s / 1.96% | 97.9% |
| `MailDateParser.parse` | 2.45 s / 7.2% | 0.862 s / 4.42% | 82.4% |
| `RFCMessageParser.parse` | 12.06 s / 35.6% | 1.963 s / 10.1% | 91.9% |
| `IngestMessageParser.parse` | 12.51 s / 36.9% | 2.764 s / 14.2% | 89.0% |

No repeated `DateFormatter` construction or configuration path appeared in the ingest window. Lazy
formatter regeneration accounted for 3 ms.

| Profiled phase | Approximate wall span |
|---|---:|
| Revision manifest | 0.17 s |
| `git cat-file` message loading | 0.27 s |
| Message parsing | 2.77 s |
| Database batch | 32.12 s |

## Warm 10k benchmark

The final measured cursor advanced exactly 10,000 ordered first-parent commits:

```text
b0626b9afc460edb199c8eb898a2579e5101ff62
    -> 345e7953df7a1536e70f5782fb4d5f642f1e7def
```

| Metric | Prior 10k baseline | New result | Change |
|---|---:|---:|---:|
| Duration | 28.96 s | 34.887 s | +20.5% |
| Throughput | 345.3/s | 286.6/s | -17.0% |
| Wall time per message | 2.90 ms | 3.489 ms | +20.3% |
| SQL calls per message | 12.88 | 12.703 | -1.4% |
| PostgreSQL execution time | approximately 4.20 s | 4.043 s | slightly lower |
| PostgreSQL execution share | 14.5% | 11.6% | lower |
| WAL per message | 8.81 KB | 6.02 KB | -31.7% |
| Person/recipient operations | 27,955 | 26,832 | -4.0% |

The workload issued 127,025 SQL calls after excluding 57 completion-monitor queries and generated
60,176,303 WAL bytes. PostgreSQL recorded no rollbacks, deadlocks, or temporary files.

This was a consecutive archive slice rather than a replay of the earlier 10,000 commits, so its
end-to-end result includes message-content and system-condition variance. PostgreSQL execution and
statement volume were slightly lower than the prior run; the wall-time regression does not point
to the optimized parser paths. The profile instead identifies sequential persistence and protocol
handling as the remaining dominant work.

## Validation and run impact

- All 36 automated tests passed.
- Git confirmed the final cursor was exactly 10,000 first-parent commits after the starting cursor
  and remained an ancestor of the epoch tip.
- The queue was empty after every completed run.
- Two excluded comparability runs were used to correct logging configuration and warm the final
  worker. Together with the retained profile and benchmark, verification advanced the real epoch-0
  cursor by 40,000 commits.
- Temporary Instruments traces and exported XML were deleted after aggregation.

## Conclusion

Both mail-parser P0 changes achieved their intended CPU effect. Mail parsing is no longer the main
ingest bottleneck, but the tested consecutive 10k slice did not improve end-to-end throughput over
the earlier 10k baseline. The next optimization should reduce the approximately 127,000 sequential
database operations, beginning with batched person and recipient persistence.
