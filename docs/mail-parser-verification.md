# MailParser Verification Report

Date: August 19, 2026  
Compatibility target: Rust `mail-parser` 0.11.6 at commit `b4366b7`

## Result

The general-purpose Swift parser and Nexus projection pass the complete
committed parity corpus on macOS and Linux. The final tree has no known P0-P2
review finding. The only build warning is the pre-existing unnecessary
`await` in `PostgresQueueJobLease.swift`.

The implementation exposes the `MailParser` library product, retains the
complete typed message/MIME result, and keeps the Vapor-facing Nexus batch
model lightweight. A missing `Message-ID` is accepted by the library and
rejected only by `IngestMessageParser`.

## Parity corpus

| Coverage | Verified result |
|---|---:|
| Complete upstream messages | 107 |
| LF and CRLF message forms | 214/214 exact projections |
| Structured-field source cases | 443 |
| LF and CRLF structured forms | 886/886 exact projections |
| Thread/base-subject vectors | 58/58 through both APIs |
| Rust charset aliases | 252/252, including normalized wire variants |
| Single-byte mappings | 7,680/7,680 |
| Multibyte candidate sequences audited | 1,726,049 |
| Rust-defined valid multibyte results | 1,209,322 exact |

The structured corpus contains all committed address, content-type, date,
message-ID, comma-list, Received, and unstructured fixtures. The complete
message corpus covers MIME traversal/classification, malformed boundaries,
transfer decoding, nested messages, attachments, body selection, and legacy
charset cases.

Focused tests additionally cover recursive Codable equality, raw offsets,
sliced `Data`, repeated headers, groups, every ID field, address encoded-word
punctuation, timezone preservation, strict IP handling, HTML conversion,
UTF-8 preview limits, concurrent parser reuse, randomized malformed bytes,
and adversarial headers. The largest targeted MIME regression uses 2,048
preceding attributes and 4,096 continuation fragments.

## Character encodings

Viceroy is pinned to version 1.1.1 and revision
`89e50c2c71d8ad0eedd4cd1bc072ec5a5e3fb7e7`. Only its Chinese, Japanese, and
Korean package traits are enabled, and the seven multibyte decoders are
selected through static APIs.

MailParser retains its own Rust-compatible label normalization, 252-alias
routing, UTF-7/UTF-16/replacement/x-user-defined behavior, and all 30
single-byte tables. Viceroy therefore replaces only the platform-sensitive
multibyte implementation rather than defining the public charset policy.

The multibyte differential audit covered Big5, EUC-JP, EUC-KR, GB18030, GBK,
ISO-2022-JP, and Shift_JIS. Every Rust-defined valid result matched. The
single-byte audit checks every byte in every advertised family. Unknown labels
continue to use lossy UTF-8.

Viceroy is an external dependency under MPL-2.0. Its exact pin and the local
adapter/corpus limit exposure to upstream API or mapping changes.

## Automated platform verification

### macOS

- Host: arm64 macOS, Apple Swift 6.4.0.
- Debug full suite: 93/93 tests passed.
- MailParser: 53/53 tests passed.
- Nexus/Postgres: 40/40 tests across 9 suites passed against PostgreSQL 18.
- Fresh profiled Release executable built successfully with debug symbols.

### Linux

- Image: official `swift:6.3.3-jammy`.
- Target: `aarch64-unknown-linux-gnu`.
- Source mounted read-only; build products stored under container `/tmp`.
- Release executable build passed.
- Release full suite: 93/93 tests across 9 suites passed against PostgreSQL 18.

No Darwin-only HTML or charset API is used. No GitHub Actions workflow was
added.

## Isolated 10,000-message benchmark

The benchmark used a fresh profiled Release executable, one server on port
8081, one queue worker, a 10,000-message database batch, and a 10,000-message
job limit. It ran only against `nexus_mailparser_benchmark`; the live `nexus`
server and its expired queue job were not touched.

The isolated cursor advanced exactly 10,000 first-parent commits:

```text
cfd9fde7c47cfe3ecbbf3277b9d2ccb81e9fa52a
    -> 0a3bdfbc7bb2323ee342c90453c4280de166f329
```

The ending commit remains an ancestor of the fixed epoch snapshot
`b67bf7f62c8125d67461cc6e7d1736ddc8844a18`. The run inserted 10,000 real
messages plus 184 expected thread placeholders. The isolated queue was empty
at completion.

| Metric | Previous reported Debug result | New profiled Release result |
|---|---:|---:|
| Messages | 10,000 | 10,000 |
| End-to-end duration | 34.887 s | 15.316 s |
| Throughput | 286.6/s | 652.9/s |
| Wall time per message | 3.489 ms | 1.532 ms |
| `IngestMessageParser.parse` inclusive sampled CPU | 2.764 s | 2.677 s |
| `MessageParser.parse` inclusive sampled CPU | n/a | 1.645 s |
| `StreamingMIMEParser.parse` inclusive sampled CPU | n/a | 1.641 s |
| Sampled parse-phase wall span | approximately 2.77 s | 2.678 s |
| Peak worker RSS | approximately 220 MiB | 224.17 MiB |

The prior report used a Debug executable, while this verification deliberately
used Release with debug symbols. End-to-end throughput is therefore not a
like-for-like performance comparison. The more useful regression signals are
that the complete parser phase remained near the previous 2.77-second span and
that peak batch memory remained near the previous 220 MiB result despite the
new parser retaining complete MIME trees during each individual projection.

Nexus releases each complete `Message` after converting it to
`IngestMailMessage`, so raw bytes, attachments, and nested messages are not
retained across the 10,000-message persistence batch.

## Safety validation

- The benchmark database ended at the expected cursor with an empty queue.
- The live database remained at cursor
  `cfd9fde7c47cfe3ecbbf3277b9d2ccb81e9fa52a` with its existing expired
  processing job unchanged.
- The benchmark server, worker, profiler, and sampler were stopped after the
  bounded run.
- No database migration or historical live-data backfill was performed.

## Reproduction artifacts

The Time Profiler trace and temporary logs were retained under
`/tmp/nexus-mailparser-benchmark.H2DpPv` for local inspection. They are not
part of the repository. The trace contains 5.057 seconds of sampled CPU;
`IngestMessageParser.parse` accounts for 2.677 seconds and its sampled wall
span is 2.678 seconds.
