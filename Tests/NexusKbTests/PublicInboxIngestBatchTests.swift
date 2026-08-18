@testable import NexusKb
import Foundation
import PostgresNIO
import Testing
import Vapor
import VaporTesting

@Suite(
    "Public-inbox database batch tests",
    .serialized
)
struct PublicInboxIngestBatchTests {
    @Test("Batch commits messages and final cursor")
    func commitsBatchAndCursor() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = try await DatabaseFixture(
                app: app
            )

            do {
                let first = try fixture.message(
                    number: 1
                )
                let second = try fixture.message(
                    number: 2
                )

                let results = try await PostgresIngestService(
                    client: app.postgres
                ).ingestBatch(
                    [first, second],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID: nil,
                    logger: app.logger
                )

                #expect(results.count == 2)
                #expect(
                    try await fixture.cursor()
                        == second.commitOID
                )
                #expect(
                    try await fixture.messageCount()
                        == 2
                )
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }

    @Test("Failure rolls back every message and cursor")
    func rollsBackBatch() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = try await DatabaseFixture(
                app: app
            )

            do {
                let first = try fixture.message(
                    number: 1
                )
                let invalid = try fixture.message(
                    number: 2,
                    invalidPatchIndex: true
                )

                do {
                    _ = try await PostgresIngestService(
                        client: app.postgres
                    ).ingestBatch(
                        [first, invalid],
                        mailingListID:
                            fixture.mailingListID,
                        epoch: fixture.epoch,
                        expectedPreviousCommitOID: nil,
                        logger: app.logger
                    )

                    Issue.record(
                        "Expected invalid patch metadata to roll back the batch"
                    )
                } catch let error as PostgresTransactionError {
                    #expect(error.closureError != nil)
                    #expect(error.rollbackError == nil)
                } catch {
                    Issue.record(
                        "Unexpected batch failure: \(error)"
                    )
                }

                #expect(
                    try await fixture.messageCount()
                        == 0
                )
                #expect(
                    try await fixture.cursor()
                        == nil
                )
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }

    @Test("Stale expected cursor cannot persist another batch")
    func rejectsStaleCursor() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = try await DatabaseFixture(
                app: app
            )

            do {
                let first = try fixture.message(
                    number: 1
                )
                let second = try fixture.message(
                    number: 2
                )
                let service = PostgresIngestService(
                    client: app.postgres
                )

                _ = try await service.ingestBatch(
                    [first],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID: nil,
                    logger: app.logger
                )

                do {
                    _ = try await service.ingestBatch(
                        [second],
                        mailingListID:
                            fixture.mailingListID,
                        epoch: fixture.epoch,
                        expectedPreviousCommitOID: nil,
                        logger: app.logger
                    )

                    Issue.record(
                        "Expected stale cursor to be rejected"
                    )
                } catch let error as PostgresTransactionError {
                    let ingestError = try #require(
                        error.closureError
                            as? PostgresIngestError
                    )

                    #expect(
                        ingestError == .cursorMismatch(
                            expected: nil,
                            actual: first.commitOID
                        )
                    )
                } catch {
                    Issue.record(
                        "Unexpected stale-cursor error: \(error)"
                    )
                }

                #expect(
                    try await fixture.cursor()
                        == first.commitOID
                )
                #expect(
                    try await fixture.messageCount()
                        == 1
                )
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }
}

private final class DatabaseFixture {
    let app: Application
    let prefix: String
    let mailingListID: Int64
    let epoch: Int32 = 2_000_000_000

    init(app: Application) async throws {
        self.app = app
        self.prefix = "nexus-kb-batch-test-\(UUID().uuidString)"

        let rows = try await app.postgres.query(
            """
            INSERT INTO mailing_lists (
                name,
                archive_group
            )
            VALUES (
                \(prefix),
                \(prefix)
            )
            RETURNING id
            """,
            logger: app.logger
        )

        var value: Int64?

        for try await row in rows {
            value = try row.decode(Int64.self)
        }

        self.mailingListID = try #require(value)
    }

    func message(
        number: Int,
        invalidPatchIndex: Bool = false
    ) throws -> PreparedPublicInboxMessage {
        let messageID = "\(prefix)-\(number)@example.com"
        let parsed = try IngestMessageParser().parse(
            Data(
                """
                From: Batch Test <batch-test@example.com>
                Message-ID: <\(messageID)>
                Subject: Batch transaction test \(number)
                Date: Tue, 18 Aug 2026 12:00:00 -0400

                Test body \(number)
                """.utf8
            )
        )

        let effectiveParsed: ParsedIngestMessage

        if invalidPatchIndex {
            effectiveParsed = ParsedIngestMessage(
                message: parsed.message,
                author: parsed.author,
                patch: ParsedPatchMetadata(
                    partIndex: -1,
                    totalParts: 1,
                    version: nil,
                    isPatchOrCover: true,
                    diff: "diff --git a/a b/a"
                )
            )
        } else {
            effectiveParsed = parsed
        }

        return PreparedPublicInboxMessage(
            commitOID:
                String(format: "%040x", number),
            blobOID:
                String(format: "%040x", number + 10_000),
            parsed: effectiveParsed
        )
    }

    func cursor() async throws -> String? {
        let rows = try await app.postgres.query(
            """
            SELECT last_scanned_commit_oid
            FROM mailing_list_archive_epochs
            WHERE mailing_list_id = \(mailingListID)
              AND epoch = \(epoch)
            """,
            logger: app.logger
        )

        for try await row in rows {
            return try row.decode(String?.self)
        }

        return nil
    }

    func messageCount() async throws -> Int64 {
        let rows = try await app.postgres.query(
            """
            SELECT count(*)::bigint
            FROM messages
            WHERE message_id LIKE \(prefix + "%")
            """,
            logger: app.logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        return 0
    }

    func remove() async throws {
        try await execute(
            """
            DELETE FROM mailing_lists
            WHERE id = \(mailingListID)
            """
        )

        try await execute(
            """
            DELETE FROM threads
            WHERE root_message_id LIKE \(prefix + "%")
            """
        )
    }

    private func execute(
        _ query: PostgresQuery
    ) async throws {
        let rows = try await app.postgres.query(
            query,
            logger: app.logger
        )

        for try await _ in rows {}
    }
}
