@testable import NexusKb
import Foundation
import PostgresNIO
import Testing
import Vapor
import VaporTesting

@Suite(
    "Patch enrichment persistence tests",
    .serialized
)
struct PostgresPatchEnrichmentServiceTests {
    @Test("Persists the complete enrichment graph")
    func persistsCompleteGraph() async throws {
        try await withPatchEnrichmentFixture {
            fixture in

            let summary = try await fixture.service
                .rebuild(
                    patchID: fixture.patchID,
                    logger: fixture.app.logger
                )
            let state = try await fixture.state()

            #expect(summary.patchID == fixture.patchID)
            #expect(
                summary.extractorVersion
                    == PatchSymbolAttributor
                        .extractorVersion
            )
            #expect(summary.fileCount == 1)
            #expect(summary.hunkCount == 1)
            #expect(summary.observationCount > 0)
            #expect(state.runCount == 1)
            #expect(state.fileCount == 1)
            #expect(state.hunkCount == 1)
            #expect(
                state.observationCount
                    == Int64(
                        summary.observationCount
                    )
            )
        }
    }

    @Test("Same extractor version replaces atomically")
    func replacesSameVersion() async throws {
        try await withPatchEnrichmentFixture {
            fixture in

            let first = try await fixture.service
                .rebuild(
                    patchID: fixture.patchID,
                    logger: fixture.app.logger
                )
            let second = try await fixture.service
                .rebuild(
                    patchID: fixture.patchID,
                    logger: fixture.app.logger
                )
            let state = try await fixture.state()

            #expect(first.runID != second.runID)
            #expect(state.runCount == 1)
            #expect(
                state.fileCount
                    == Int64(second.fileCount)
            )
            #expect(
                state.hunkCount
                    == Int64(second.hunkCount)
            )
            #expect(
                state.observationCount
                    == Int64(
                        second.observationCount
                    )
            )
        }
    }

    @Test("Deletion is scoped by extractor version")
    func deletesOnlyRequestedVersion() async throws {
        try await withPatchEnrichmentFixture {
            fixture in

            _ = try await fixture.service.rebuild(
                patchID: fixture.patchID,
                logger: fixture.app.logger
            )
            try await fixture.insertLegacyRun()

            #expect(
                try await fixture.service.delete(
                    patchID: fixture.patchID,
                    extractorVersion:
                        PatchSymbolAttributor
                        .extractorVersion,
                    logger: fixture.app.logger
                )
            )
            #expect(
                try await !fixture.service.delete(
                    patchID: fixture.patchID,
                    extractorVersion:
                        PatchSymbolAttributor
                        .extractorVersion,
                    logger: fixture.app.logger
                )
            )
            #expect(
                try await fixture.versions()
                    == ["legacy-test/1"]
            )

            let state = try await fixture.state()

            #expect(state.runCount == 1)
            #expect(state.fileCount == 0)
            #expect(state.hunkCount == 0)
            #expect(state.observationCount == 0)
        }
    }

    @Test("Canonical patch deletion cascades derived data")
    func canonicalPatchDeletionCascades() async throws {
        try await withPatchEnrichmentFixture {
            fixture in

            _ = try await fixture.service.rebuild(
                patchID: fixture.patchID,
                logger: fixture.app.logger
            )
            try await fixture.deletePatch()

            let state = try await fixture.state()

            #expect(state.runCount == 0)
            #expect(state.fileCount == 0)
            #expect(state.hunkCount == 0)
            #expect(state.observationCount == 0)
        }
    }
}

private struct PatchEnrichmentDatabaseState {
    let runCount: Int64
    let fileCount: Int64
    let hunkCount: Int64
    let observationCount: Int64
}

private struct PatchEnrichmentDatabaseFixture {
    static let legacyVersion = "legacy-test/1"

    let app: Application
    let threadID: Int64
    let patchID: Int64

    var service: PostgresPatchEnrichmentService {
        PostgresPatchEnrichmentService(
            client: app.postgres
        )
    }

    static func create(
        app: Application
    ) async throws -> Self {
        let prefix = "patch-enrichment-\(UUID())"
        let messageID = "\(prefix)@example.com"
        let threadID = try await insertedID(
            """
            INSERT INTO threads (
                root_message_id,
                subject,
                last_updated_at
            )
            VALUES (
                \(messageID),
                'Patch enrichment test',
                now()
            )
            RETURNING id
            """,
            app: app
        )

        try await execute(
            """
            INSERT INTO messages (
                message_id,
                thread_id,
                subject,
                body
            )
            VALUES (
                \(messageID),
                \(threadID),
                '[PATCH] kernel: persistence fixture',
                \(patchDiff)
            )
            """,
            app: app
        )

        let patchSetID = try await insertedID(
            """
            INSERT INTO patchsets (
                thread_id,
                subject,
                status,
                total_parts,
                received_parts,
                subject_index,
                parser_version
            )
            VALUES (
                \(threadID),
                '[PATCH] kernel: persistence fixture',
                'Complete',
                1,
                1,
                1,
                \(ParsedPatchMetadata.parserVersion)
            )
            RETURNING id
            """,
            app: app
        )
        let patchID = try await insertedID(
            """
            INSERT INTO patches (
                patchset_id,
                message_id,
                part_index,
                diff
            )
            VALUES (
                \(patchSetID),
                \(messageID),
                1,
                \(patchDiff)
            )
            RETURNING id
            """,
            app: app
        )

        return Self(
            app: app,
            threadID: threadID,
            patchID: patchID
        )
    }

    func state() async throws
        -> PatchEnrichmentDatabaseState
    {
        let rows = try await app.postgres.query(
            """
            SELECT
                (
                    SELECT count(*)
                    FROM enrichment_runs
                    WHERE patch_id = \(patchID)
                ),
                (
                    SELECT count(*)
                    FROM patch_diff_files
                    WHERE patch_id = \(patchID)
                ),
                (
                    SELECT count(*)
                    FROM patch_diff_hunks
                    WHERE patch_id = \(patchID)
                ),
                (
                    SELECT count(*)
                    FROM patch_symbol_observations
                    WHERE patch_id = \(patchID)
                )
            """,
            logger: app.logger
        )

        for try await row in rows {
            let value = try row.decode(
                (
                    Int64,
                    Int64,
                    Int64,
                    Int64
                ).self
            )

            return PatchEnrichmentDatabaseState(
                runCount: value.0,
                fileCount: value.1,
                hunkCount: value.2,
                observationCount: value.3
            )
        }

        return PatchEnrichmentDatabaseState(
            runCount: 0,
            fileCount: 0,
            hunkCount: 0,
            observationCount: 0
        )
    }

    func insertLegacyRun() async throws {
        try await Self.execute(
            """
            INSERT INTO enrichment_runs (
                patch_id,
                extractor_version
            )
            VALUES (
                \(patchID),
                \(Self.legacyVersion)
            )
            """,
            app: app
        )
    }

    func versions() async throws -> [String] {
        let rows = try await app.postgres.query(
            """
            SELECT extractor_version
            FROM enrichment_runs
            WHERE patch_id = \(patchID)
            ORDER BY extractor_version
            """,
            logger: app.logger
        )
        var values: [String] = []

        for try await row in rows {
            values.append(
                try row.decode(String.self)
            )
        }

        return values
    }

    func deletePatch() async throws {
        try await Self.execute(
            """
            DELETE FROM patches
            WHERE id = \(patchID)
            """,
            app: app
        )
    }

    func remove() async throws {
        try await Self.execute(
            """
            DELETE FROM threads
            WHERE id = \(threadID)
            """,
            app: app
        )
    }

    private static func insertedID(
        _ query: PostgresQuery,
        app: Application
    ) async throws -> Int64 {
        let rows = try await app.postgres.query(
            query,
            logger: app.logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        throw
            PostgresPatchEnrichmentError
            .missingInsertedRun
    }

    private static func execute(
        _ query: PostgresQuery,
        app: Application
    ) async throws {
        let rows = try await app.postgres.query(
            query,
            logger: app.logger
        )

        for try await _ in rows {}
    }

    private static let patchDiff = """
        kernel: persist enriched patch data

        Signed-off-by: Test Author <test@example.com>
        ---
        diff --git a/kernel/sample.c b/kernel/sample.c
        index 111111111111..222222222222 100644
        --- a/kernel/sample.c
        +++ b/kernel/sample.c
        @@ -1,4 +1,4 @@ static int sample_worker(void)
         static int sample_worker(void)
         {
        -\treturn old_helper();
        +\treturn new_helper();
         }
        """
}

private func withPatchEnrichmentFixture(
    _ body: (PatchEnrichmentDatabaseFixture)
        async throws -> Void
) async throws {
    try await withApp(
        configure: configure
    ) { app in
        let fixture = try await
            PatchEnrichmentDatabaseFixture
            .create(app: app)

        do {
            try await body(fixture)
        } catch {
            try? await fixture.remove()
            throw error
        }

        try await fixture.remove()
    }
}
