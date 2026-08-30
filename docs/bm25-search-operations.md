# Thread-level mailing-list BM25 search

This document records the PostgreSQL runtime migration, backup, corpus
evidence, thread-document design, backfill, API behavior, measurements, and
rollback. Search is limited to ParadeDB BM25. Nexus does not implement
semantic search, embeddings, vector indexes, hybrid search, RRF, or reranking.

## Runtime

PostgreSQL runs under Apple's `container` CLI with the existing PGDATA bind
mount.

| Setting | Value |
| --- | --- |
| Image | `docker.io/paradedb/paradedb:0.25.6-pg18` |
| Image index digest | `sha256:c5b04eba22497fa25de12265692e9578e309c2e2001d023ce6d08a17226c200a` |
| Platform | `linux/arm64` |
| PostgreSQL | 18.6 |
| `pg_search` | 0.25.6 |
| PGDATA mount | `/Users/tansanrao/work/postgres-data:/var/lib/postgresql` |
| Host port | 5432 |
| Resources | 4 CPUs, 8 GiB memory |
| PostgreSQL buffer pool | 2 GiB (`shared_buffers`) |

`pg_search` 0.25.6 declares `vector` as an installation dependency, so
`CREATE EXTENSION pg_search CASCADE` also installs `vector` 0.8.4. Nexus has
no vector column, vector index, or vector query path.

Start the pinned runtime:

```bash
container run \
  --name postgres18 \
  --platform linux/arm64 \
  --cpus 4 \
  --memory 8G \
  --env-file .env \
  -e POSTGRES_DB=nexus \
  --volume /Users/tansanrao/work/postgres-data:/var/lib/postgresql \
  --publish 0.0.0.0:5432:5432 \
  --detach \
  docker.io/paradedb/paradedb:0.25.6-pg18 \
  postgres \
    -c shared_preload_libraries=pg_search,pg_stat_statements \
    -c shared_buffers=2GB
```

The explicit preload setting is required when reusing PGDATA initialized by
the stock PostgreSQL image. A 1 GiB container with the default 128 MiB buffer
pool was insufficient: the original parallel BM25 build reached 96.7% and
failed with `no unpinned buffers available`. The failed statement left no
partial index. An 8 GiB cap and 2 GiB buffer pool completed subsequent builds.

## Recoverable pre-migration backup

The backup is outside the repository at:

```text
/Users/tansanrao/work/nexus-backups/2026-08-30-pre-paradedb/
```

Important files:

- `nexus.dump`: 9,333,309,033-byte PostgreSQL 18 custom archive, Zstandard 6
- `globals.sql`: roles and globals without role passwords
- `baseline.tsv`: pre-migration counts and database size
- `SHA256SUMS`: checksums for all recovery inputs
- `nexus.dump.list`: successfully decoded 208-entry archive TOC
- `restore-verification.tsv` and `RESTORE_VALIDATED`: isolated restore proof
- runtime inspections and backfill/index/query verification logs

`nexus.dump` has SHA-256
`784b79e9d093c6c70a88e5524786b9639177212ed3f950942aeb59981b7be06b`.
It was restored with `pg_restore --jobs=4 --exit-on-error` into an isolated
database. Every constraint validated and these cardinalities matched:

| Relation/set | Source | Restored |
| --- | ---: | ---: |
| Threads | 1,132,432 | 1,132,432 |
| Messages | 6,622,615 | 6,622,615 |
| Real messages | 6,559,514 | 6,559,514 |
| Placeholder messages | 63,101 | 63,101 |
| Mailing-list links | 6,640,638 | 6,640,638 |
| Patch sets | 960,857 | 960,857 |
| Patches | 2,345,296 | 2,345,296 |

The immutable backup includes one leaked maintenance-test thread that was
identified and removed after migration. Current corpus counts below exclude
that fixture; restoring the backup also restores it.

Before restoring, run `shasum -a 256 -c SHA256SUMS` in the backup directory.

## Thread-structure evidence

Nexus's search identity is `threads.id`, not an individual email. A thread's
root is `threads.root_message_id`; `messages.thread_id` stores membership and
`messages.in_reply_to` stores the parent edge. `references_ids` is retained as
message metadata but is not the canonical tree edge. Ingestion can create a
placeholder root when a reply arrives first and can later merge the whole
thread when the missing parent appears.

Measured on the retained production data:

| Measurement | Result |
| --- | ---: |
| Threads | 1,132,431 |
| Threads with a real root | 1,069,334 |
| Threads with a placeholder root | 63,097 |
| Root messages (depth 0) | 1,069,334 |
| Direct children (depth 1) | 2,484,852 |
| Second-level replies (depth 2) | 1,032,657 |
| Raw characters at depths 0 / 1 / 2 | 5.12B / 11.57B / 3.35B |
| Body-length p50 / p90 / p99 at depth 0 | 1,790 / 8,627 / 47,623 |
| Body-length p50 / p90 / p99 at depth 1 | 1,918 / 8,305 / 42,484 |
| Body-length p50 / p90 / p99 at depth 2 | 1,606 / 6,466 / 26,607 |
| Stored patch payloads | 2,345,296 |
| Messages with `diff --git` | 2,101,503 |
| Messages with paired `---` / `+++` markers | 2,465,746 |
| Messages containing `>` quote lines | 3,697,537 |

The lore mirrors confirm why the search text cannot be a concatenation of all
messages. LKML blob `038896f0d8fbed7799798726c69b0a5499b7a296` is message
`61537689daa428a577e6bdab794d044f5405128e.camel@collabora.com`. Its new prose
is interleaved with nested `>`, `> >`, and `> > >` copies of earlier discussion
and patch code. Indexing that reply verbatim would count ancestor text again.

The same VPU720 thread demonstrates the selected depth boundary:

```text
cover letter (depth 0)
└── patch email (depth 1)
    └── first review reply (depth 2)
        └── later replies (depth 3+, excluded)
```

The 60,346-character VPU720 patch becomes 2,403 searchable characters after
the patch payload is removed. `VDPU720_REG_VERSION`, present only in the diff
or quoted copies, is absent. Cover-letter prose, patch commit messages, and
new review discussion remain.

## `thread_search_documents` design

Migration `0011_thread_search_documents.sql` creates exactly one search row
per thread with a real root:

```text
thread_search_documents
├── thread_id  primary key and ParadeDB key
├── subject    real root-message subject
└── content    root body + reply depths 1 and 2
```

One document per thread is deliberate:

- BM25 returns a thread directly, so the API never deduplicates message or
  chunk hits and never shows the same thread twice.
- The root subject is stored once in its own indexed field.
- Content is ordered by reply depth, timestamp, and database message ID for a
  deterministic idempotent rebuild.
- Threads with placeholder roots are omitted because root author, subject,
  date, and cover text are unknown.

`search_thread_message_text(body)` removes only syntax with strong structural
evidence:

- all lines beginning with optional whitespace and one or more `>` markers;
- a multilingual reply attribution only when the following line is quoted;
- content after an `Original Message` or `Forwarded message` marker;
- patch payload beginning at `diff --git`, `Index:`, `GIT binary patch`, paired
  unified `---` / `+++` paths, or paired context-diff `***` / `---` paths.

A line containing only `---` is retained, so cover-letter separators and prose
before a diff are searchable. Signatures are retained when no diff precedes
them because a signature is not evidence of repeated ancestor text.

Statement-level insert, update, and delete triggers collect distinct affected
thread IDs and rebuild each document once per SQL statement. A thread-root
change also refreshes the document. Thread deletion is handled by the
document foreign key's `ON DELETE CASCADE`.

Migration `0012_thread_search_bm25.sql` creates the sole ParadeDB index on
`thread_id`, `subject`, and `content`, with `thread_id` as the unique key.

## Apply and backfill

Apply the document schema first:

```bash
container exec -i postgres18 psql \
  -U postgres -d nexus -X \
  -v ON_ERROR_STOP=1 \
  --single-transaction --file=- \
  < Sources/NexusKb/Migrations/0011_thread_search_documents.sql
```

Backfill in bounded, rerunnable thread-ID ranges before creating BM25. The
refresh function deletes and regenerates the requested documents in one
transaction, so interruption cannot produce duplicate or partially rebuilt
rows.

```bash
max_id=$(container exec postgres18 psql \
  -U postgres -d nexus -X -At \
  -c 'SELECT max(id) FROM threads')

minimum=1
batch_size=10000
while test "$minimum" -le "$max_id"; do
  maximum=$((minimum + batch_size - 1))
  test "$maximum" -le "$max_id" || maximum=$max_id

  container exec postgres18 psql \
    -U postgres -d nexus -X -At \
    -v ON_ERROR_STOP=1 \
    -c "SELECT refresh_thread_search_documents(
          COALESCE(
            (SELECT array_agg(id) FROM threads
             WHERE id BETWEEN $minimum AND $maximum),
            ARRAY[]::bigint[]
          )
        )"

  minimum=$((maximum + 1))
done
```

Create BM25 after the backfill:

```bash
container exec -i postgres18 psql \
  -U postgres -d nexus -X \
  -v ON_ERROR_STOP=1 \
  --file=- \
  < Sources/NexusKb/Migrations/0012_thread_search_bm25.sql
```

After deploying `/api/v1/search`, remove the retired thread-subject GIN path:

```bash
container exec -i postgres18 psql \
  -U postgres -d nexus -X \
  -v ON_ERROR_STOP=1 \
  --file=- \
  < Sources/NexusKb/Migrations/0013_remove_legacy_thread_search.sql
```

Migration 0013 retains `messages.author_search` and
`messages_author_search_idx`; the new endpoint uses them only as a root-author
metadata filter.

Verify coverage and physical index integrity:

```sql
SELECT
    count(*) AS documents,
    max(length(content)) AS largest_document
FROM thread_search_documents;

SELECT count(*) AS missing_real_root_threads
FROM threads AS thread
JOIN messages AS root
  ON root.message_id = thread.root_message_id
 AND NOT root.is_placeholder
WHERE NOT EXISTS (
    SELECT 1
    FROM thread_search_documents AS document
    WHERE document.thread_id = thread.id
);

VACUUM (
    ANALYZE,
    INDEX_CLEANUP ON
) thread_search_documents;

SELECT *
FROM pdb.verify_index(
    'thread_search_documents_bm25_idx',
    heapallindexed := true
);
```

Forced index cleanup is useful after tests that insert, refresh, and delete
fixture threads; otherwise physically dead BM25 entries can remain until a
later vacuum even though they are not query-visible.

## Search API and WebUI

`GET /api/v1/search` is the only search endpoint. `GET /api/v1/threads`
remains chronological browsing. Passing `q` to `/threads` returns HTTP 400
with the replacement endpoint rather than silently invoking the retired path.

| Query form | Thread-level behavior |
| --- | --- |
| unscoped tokens | BM25 over root subject and depth-0-to-2 cleaned content |
| `subject:<value>` | BM25 scoped to the real root subject |
| `author:<value>` | filter on the real root author |
| `date:YYYY-MM-DD` | filter on the real root's UTC calendar day |
| `date:start..end` | inclusive UTC root-date range |
| `date:start..` / `date:..end` | open-ended UTC root-date range |

Quote multi-word selectors, for example `subject:"grace period"` and
`author:"Paul E. McKenney"`. Selectors can be combined. Author/date-only
queries return root-filtered threads newest-first with score zero.

`mailingList=<archive-group>` requires any message in the thread to be linked
to that lore archive. `limit` defaults to 25 and accepts 1 through 100. Opaque
offset cursors embed the normalized query, mailing-list filter, and page size;
reusing a cursor with a different explicit scope returns HTTP 400.

When no root-metadata or mailing-list filter is present, text and subject
searches materialize ParadeDB's top ranked IDs before fetching thread
summaries. This preserves `TopKScanExecState` for the common path. Searches
with author, date, or mailing-list constraints apply those predicates before
the result limit, so filtering cannot hide a qualifying lower-ranked thread.

Each result extends the standard thread-summary representation with only
`score` and `snippet`. It includes root identity and metadata, activity time,
message counts, mailing lists, subsystems, and patch-series summaries. The
Solid WebUI renders the same thread row used for chronological browsing and
adds score and matching thread text.

Example:

```bash
curl --get http://127.0.0.1:8080/api/v1/search \
  --data-urlencode 'q=VPU720 subject:"JPEG decoder" author:hauer date:2026-08-01..' \
  --data-urlencode 'mailingList=linux-kernel' \
  --data 'limit=10'
```

## Measured final result

| Measurement | Result |
| --- | ---: |
| Backfill window | 2026-08-30 16:53:03–17:03:02 UTC |
| Backfill duration | 9m 59s |
| Thread-ID range and batch size | 1–1,162,998; 10,000 IDs |
| Search documents / distinct IDs | 1,069,334 / 1,069,334 |
| Missing real-root threads / placeholder-root documents | 0 / 0 |
| Searchable characters | 5,167,900,166 |
| Content-length p50 / p90 / p99 | 1,552 / 9,926 / about 49,870 characters |
| Largest document | 3,188,692 characters |
| Relation before BM25, including TOAST and primary key | 2,902,458,368 bytes |
| BM25 index | 2,900,000,768 bytes |
| Relation after BM25 | 5,855,150,080 bytes |
| Database before search / final | 42,825,209,535 / 48,629,388,991 bytes |
| BM25 build window | 2026-08-30 17:04:30–17:06:14 UTC |
| BM25 build duration | 1m 44s with two parallel workers |

Rerunning thread IDs 1–10,000 produced 9,179 documents both times. The
thread-ID sum, subject/content lengths, and seeded subject/content hash sums
were identical before and after refresh. This proves deterministic,
idempotent final state independently of row order.

Representative first executions after the index build:

| Query | Time | Top result | Top score |
| --- | ---: | --- | ---: |
| `handle_mm_fault` | 75.080 ms | `[PATCH] Export handle_mm_fault to modules.` | 24.055 |
| `Rockchip VPU720` | 7.221 ms | `[PATCH 0/7] media: verisilicon: Add RK3588 VPU720 JPEG decoder` | 43.398 |
| `VDPU720_REG_VERSION` | 4.323 ms | no result; token exists only in removed diff/quotes | — |
| `scheduler latency regression` | 36.196 ms | `Database regression due to scheduler changes ?` | 30.563 |

An `EXPLAIN (ANALYZE, BUFFERS)` of the optimized unfiltered
`handle_mm_fault` path used `thread_search_documents_bm25_idx`,
`TopKScanExecState`, 26 heap fetches for the API's default page plus lookahead,
and completed in 10.399 ms after warm-up. The root-summary join occurred only
after that bounded ranked result.

After the final fixture cleanup and forced vacuum,
`pdb.verify_index(..., heapallindexed := true)` passed all six checks: schema,
readability, segment checksums, metadata for six segments, 1,069,334 valid
CTIDs, and 1,069,334 live heap references. After removing the leaked test
fixture, source cardinalities are 1,132,431 threads and 6,622,614 messages
(6,559,513 real and 63,101 placeholder).

The integration fixture proves all contract boundaries in one test: a token
in a depth-2 reply finds its thread once; quoted text, a patch-diff token, and
a depth-3 token produce no result; child-only subject/author/date values do not
satisfy root filters; subject scope, combined filters, filter-only results,
pagination, and idempotent refresh all pass.

## Rollback

### Remove thread search while retaining ParadeDB

Stop application writes, then remove objects in dependency order:

```sql
DROP INDEX IF EXISTS thread_search_documents_bm25_idx;
DROP TRIGGER IF EXISTS messages_sync_thread_search_after_insert ON messages;
DROP TRIGGER IF EXISTS messages_sync_thread_search_after_update ON messages;
DROP TRIGGER IF EXISTS messages_sync_thread_search_after_delete ON messages;
DROP TRIGGER IF EXISTS threads_sync_thread_search_after_root_update ON threads;
DROP FUNCTION IF EXISTS sync_thread_search_documents_after_insert();
DROP FUNCTION IF EXISTS sync_thread_search_documents_after_update();
DROP FUNCTION IF EXISTS sync_thread_search_documents_after_delete();
DROP FUNCTION IF EXISTS sync_thread_search_document_for_thread();
DROP FUNCTION IF EXISTS refresh_thread_search_documents(bigint[]);
DROP FUNCTION IF EXISTS search_thread_message_text(text);
DROP TABLE IF EXISTS thread_search_documents;
DROP EXTENSION IF EXISTS pg_search;
DROP EXTENSION IF EXISTS vector;
```

Drop `vector` only if no other feature uses it.

To roll application code back to the legacy `/threads?q=...` implementation,
recreate the generated root-subject column and index removed by migration 0013:

```sql
ALTER TABLE threads
ADD COLUMN subject_search tsvector
GENERATED ALWAYS AS (
    to_tsvector('simple', COALESCE(subject, ''))
) STORED;

CREATE INDEX threads_subject_search_idx
ON threads
USING GIN (subject_search);

ANALYZE threads (subject_search);
```

### Restore the stock runtime and pre-migration database

The safest complete rollback is a logical restore into fresh PGDATA. It avoids
an unsupported PostgreSQL 18.6-to-18.4 minor downgrade and removes all
ParadeDB catalog and WAL state.

1. Stop Nexus writers and `postgres18`.
2. Rename `/Users/tansanrao/work/postgres-data` to a timestamped retained path.
3. Create a fresh `/Users/tansanrao/work/postgres-data`.
4. Start the captured stock arm64 PostgreSQL image.
5. Verify checksums and restore `nexus.dump`.

```bash
backup=/Users/tansanrao/work/nexus-backups/2026-08-30-pre-paradedb

(cd "$backup" && shasum -a 256 -c SHA256SUMS)

container stop postgres18
container delete postgres18
mv /Users/tansanrao/work/postgres-data \
  "/Users/tansanrao/work/postgres-data-paradedb-$(date +%Y%m%d-%H%M%S)"
mkdir /Users/tansanrao/work/postgres-data

container run \
  --name postgres18 \
  --platform linux/arm64 \
  --cpus 4 \
  --memory 8G \
  --env-file .env \
  -e POSTGRES_DB=nexus \
  --volume /Users/tansanrao/work/postgres-data:/var/lib/postgresql \
  --publish 0.0.0.0:5432:5432 \
  --detach \
  docker.io/library/postgres:18@sha256:a02db8cac496f15b094798a38254f14d6e00741f709360e5e00bb6668ea31636 \
  postgres -c shared_buffers=2GB

until container exec postgres18 pg_isready -U postgres -d nexus; do
  sleep 1
done

container copy "$backup/nexus.dump" postgres18:/tmp/nexus.dump
container exec postgres18 pg_restore \
  -U postgres -d nexus \
  --jobs=4 --exit-on-error \
  --clean --if-exists --no-owner --no-acl \
  /tmp/nexus.dump
container exec postgres18 rm /tmp/nexus.dump
```

Finally compare all baseline cardinalities and run the read/search API checks
before deleting any retained ParadeDB PGDATA directory.
