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

    @Test("Deletion retracts an orphan and advances the cursor")
    func retractsDeletedOrphan() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = try await DatabaseFixture(
                app: app
            )

            do {
                let message = try fixture.message(
                    number: 1
                )
                let deletionCommit =
                    String(repeating: "f", count: 40)
                let service = PostgresIngestService(
                    client: app.postgres
                )

                _ = try await service.ingestBatch(
                    [message],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID: nil,
                    logger: app.logger
                )

                _ = try await service.ingestBatch(
                    [
                        .deletion(
                            commitOID: deletionCommit,
                            blobOID: message.blobOID
                        )
                    ],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID:
                        message.commitOID,
                    logger: app.logger
                )

                #expect(
                    try await fixture.cursor()
                        == deletionCommit
                )
                #expect(
                    try await fixture.messageState(
                        messageID:
                            message.parsed.message
                            .messageID
                    ) == nil
                )
                #expect(
                    try await fixture.threadCount() == 0
                )
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }

    @Test("Deleted parent becomes a placeholder")
    func deletedParentBecomesPlaceholder() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = try await DatabaseFixture(
                app: app
            )

            do {
                let parent = try fixture.message(
                    number: 1
                )
                let reply = try fixture.message(
                    number: 2,
                    inReplyTo:
                        parent.parsed.message
                        .messageID
                )
                let deletionCommit =
                    String(repeating: "e", count: 40)
                let service = PostgresIngestService(
                    client: app.postgres
                )

                _ = try await service.ingestBatch(
                    [parent, reply],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID: nil,
                    logger: app.logger
                )

                _ = try await service.ingestBatch(
                    [
                        .deletion(
                            commitOID: deletionCommit,
                            blobOID: parent.blobOID
                        )
                    ],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID:
                        reply.commitOID,
                    logger: app.logger
                )

                let parentState = try await fixture
                    .messageState(
                        messageID:
                            parent.parsed.message
                            .messageID
                    )

                #expect(
                    parentState?.isPlaceholder == true
                )
                #expect(
                    try await fixture.mailingListBlobOID(
                        messageID:
                            parent.parsed.message
                            .messageID
                    ) == nil
                )
                #expect(
                    try await fixture.messageState(
                        messageID:
                            reply.parsed.message
                            .messageID
                    )?.isPlaceholder == false
                )
                #expect(
                    try await fixture.cursor()
                        == deletionCommit
                )
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }

    @Test("Deletion preserves a message linked to another list")
    func preservesCrossListMessage() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = try await DatabaseFixture(
                app: app
            )

            do {
                let message = try fixture.message(
                    number: 1
                )
                let otherMailingListID =
                    try await fixture
                    .createAdditionalMailingList()
                let service = PostgresIngestService(
                    client: app.postgres
                )

                _ = try await service.ingestBatch(
                    [message],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID: nil,
                    logger: app.logger
                )

                _ = try await service.ingestBatch(
                    [message],
                    mailingListID:
                        otherMailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID: nil,
                    logger: app.logger
                )

                _ = try await service.ingestBatch(
                    [
                        .deletion(
                            commitOID:
                                String(
                                    repeating: "d",
                                    count: 40
                                ),
                            blobOID: message.blobOID
                        )
                    ],
                    mailingListID:
                        fixture.mailingListID,
                    epoch: fixture.epoch,
                    expectedPreviousCommitOID:
                        message.commitOID,
                    logger: app.logger
                )

                #expect(
                    try await fixture.mailingListBlobOID(
                        messageID:
                            message.parsed.message
                            .messageID
                    ) == nil
                )
                #expect(
                    try await fixture.mailingListBlobOID(
                        messageID:
                            message.parsed.message
                            .messageID,
                        mailingListID:
                            otherMailingListID
                    ) == message.blobOID
                )
                #expect(
                    try await fixture.messageState(
                        messageID:
                            message.parsed.message
                            .messageID
                    )?.isPlaceholder == false
                )
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }
}

private struct TestPerson {
    let id: Int64
    let name: String?
    let email: String
}

private struct TestRecipient {
    let email: String
    let type: String
}

private struct TestMessageState {
    let threadID: Int64
    let isPlaceholder: Bool
}

private struct TestThreadMetadata {
    let subject: String?
    let lastUpdatedAt: Date
}

private final class DatabaseFixture {
    let app: Application
    let prefix: String
    let mailingListID: Int64
    let epoch: Int32 = 2_000_000_000
    private var additionalMailingListIDs: [Int64] = []

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
        messageID: String? = nil,
        inReplyTo: String? = nil,
        to: [String] = [],
        cc: [String] = [],
        subject: String? = nil,
        dateHeader: String =
            "Tue, 18 Aug 2026 12:00:00 -0400",
        invalidPatchIndex: Bool = false
    ) throws -> PreparedPublicInboxMessage {
        let resolvedMessageID =
            messageID
            ?? "\(prefix)-\(number)@example.com"

        let resolvedSubject =
            subject
            ?? "Batch transaction test \(number)"

        var headerLines = [
            "From: Batch Test <batch-test@example.com>",
            "Message-ID: <\(resolvedMessageID)>",
            "Subject: \(resolvedSubject)",
            "Date: \(dateHeader)",
        ]

        if let inReplyTo {
            headerLines.append(
                "In-Reply-To: <\(inReplyTo)>"
            )
        }

        if !to.isEmpty {
            headerLines.append(
                "To: \(to.joined(separator: ", "))"
            )
        }

        if !cc.isEmpty {
            headerLines.append(
                "Cc: \(cc.joined(separator: ", "))"
            )
        }

        let rawMessage =
            headerLines.joined(
                separator: "\r\n"
            )
            + "\r\n\r\n"
            + "Test body \(number)\r\n"

        let parsed = try IngestMessageParser()
            .parse(
                Data(rawMessage.utf8)
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
                String(
                    format: "%040x",
                    number
                ),
            blobOID:
                String(
                    format: "%040x",
                    number + 10_000
                ),
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

    func createAdditionalMailingList()
        async throws -> Int64
    {
        let rows = try await app.postgres.query(
            """
            INSERT INTO mailing_lists (
                name,
                archive_group
            )
            VALUES (
                \(prefix + "-additional"),
                \(prefix + "-additional")
            )
            RETURNING id
            """,
            logger: app.logger
        )

        var value: Int64?

        for try await row in rows {
            value = try row.decode(Int64.self)
        }

        let mailingListID = try #require(value)

        additionalMailingListIDs.append(
            mailingListID
        )

        return mailingListID
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
        for mailingListID
            in additionalMailingListIDs
        {
            try await execute(
                """
                DELETE FROM mailing_lists
                WHERE id = \(mailingListID)
                """
            )
        }

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
        try await execute(
            """
            DELETE FROM people
            WHERE lower(email) LIKE
                lower(\(prefix + "%"))
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

    func people(
        email: String
    ) async throws -> [TestPerson] {
        let rows = try await app.postgres.query(
            """
            SELECT
                id,
                name,
                email
            FROM people
            WHERE lower(email) =
                lower(\(email))
            ORDER BY id
            """,
            logger: app.logger
        )

        var people: [TestPerson] = []

        for try await row in rows {
            let value = try row.decode(
                (
                    Int64,
                    String?,
                    String
                ).self
            )

            people.append(
                TestPerson(
                    id: value.0,
                    name: value.1,
                    email: value.2
                )
            )
        }

        return people
    }

    func recipients(
        messageID: String
    ) async throws -> [TestRecipient] {
        let rows = try await app.postgres.query(
            """
            SELECT
                lower(person.email),
                recipient.recipient_type
            FROM messages_recipients
                AS recipient
            JOIN messages AS message
              ON message.id =
                    recipient.message_id
            JOIN people AS person
              ON person.id =
                    recipient.person_id
            WHERE message.message_id =
                \(messageID)
            ORDER BY
                lower(person.email),
                recipient.recipient_type
            """,
            logger: app.logger
        )

        var recipients: [TestRecipient] = []

        for try await row in rows {
            let value = try row.decode(
                (String, String).self
            )

            recipients.append(
                TestRecipient(
                    email: value.0,
                    type: value.1
                )
            )
        }

        return recipients
    }

    func messageState(
        messageID: String
    ) async throws -> TestMessageState? {
        let rows = try await app.postgres.query(
            """
            SELECT
                thread_id,
                is_placeholder
            FROM messages
            WHERE message_id = \(messageID)
            """,
            logger: app.logger
        )

        for try await row in rows {
            let value = try row.decode(
                (Int64, Bool).self
            )

            return TestMessageState(
                threadID: value.0,
                isPlaceholder: value.1
            )
        }

        return nil
    }

    func mailingListBlobOID(
        messageID: String,
        mailingListID: Int64? = nil
    ) async throws -> String? {
        let targetMailingListID =
            mailingListID ?? self.mailingListID

        let rows = try await app.postgres.query(
            """
            SELECT link.archive_blob_oid
            FROM messages_mailing_lists
                AS link
            JOIN messages AS message
              ON message.id =
                    link.message_id
            WHERE message.message_id =
                    \(messageID)
              AND link.mailing_list_id =
                    \(targetMailingListID)
            """,
            logger: app.logger
        )

        for try await row in rows {
            return try row.decode(
                String?.self
            )
        }

        return nil
    }

    func threadMetadata(
        messageID: String
    ) async throws -> TestThreadMetadata? {
        let rows = try await app.postgres.query(
            """
            SELECT
                thread.subject,
                thread.last_updated_at
            FROM threads AS thread
            JOIN messages AS message
              ON message.thread_id =
                    thread.id
            WHERE message.message_id =
                    \(messageID)
            """,
            logger: app.logger
        )

        for try await row in rows {
            let value = try row.decode(
                (String?, Date).self
            )

            return TestThreadMetadata(
                subject: value.0,
                lastUpdatedAt: value.1
            )
        }

        return nil
    }

    func threadCount() async throws -> Int64 {
        let rows = try await app.postgres.query(
            """
            SELECT count(*)::bigint
            FROM threads
            WHERE root_message_id LIKE
                \(prefix + "%")
            """,
            logger: app.logger
        )

        for try await row in rows {
            return try row.decode(
                Int64.self
            )
        }

        return 0
    }
}

@Test(
    "Batch resolves each person once and preserves typed links"
)
func batchesPeopleAndRecipients() async throws {
    try await withApp(
        configure: configure
    ) { app in
        let fixture = try await DatabaseFixture(
            app: app
        )

        do {
            let sharedEmail =
                "\(fixture.prefix)-shared@example.com"

            let first = try fixture.message(
                number: 1,
                to: [
                    "First Name <\(sharedEmail)>",
                    "Duplicate Name <\(sharedEmail.uppercased())>",
                ],
                cc: [
                    "Cc Name <\(sharedEmail)>"
                ]
            )

            let second = try fixture.message(
                number: 2,
                to: [
                    "Final Name <\(sharedEmail.uppercased())>"
                ]
            )

            _ = try await PostgresIngestService(
                client: app.postgres
            ).ingestBatch(
                [first, second],
                mailingListID:
                    fixture.mailingListID,
                epoch: fixture.epoch,
                expectedPreviousCommitOID: nil,
                logger: app.logger
            )

            let people = try await fixture.people(
                email: sharedEmail
            )

            #expect(people.count == 1)
            #expect(
                people.first?.name
                    == "Final Name"
            )
            #expect(
                people.first?.email
                    == sharedEmail
            )

            let firstRecipients =
                try await fixture.recipients(
                    messageID:
                        first.parsed.message
                        .messageID
                )

            #expect(
                firstRecipients.count == 2
            )
            #expect(
                firstRecipients.contains {
                    $0.type
                        == RecipientType
                        .to
                        .rawValue
                }
            )
            #expect(
                firstRecipients.contains {
                    $0.type
                        == RecipientType
                        .cc
                        .rawValue
                }
            )

            let secondRecipients =
                try await fixture.recipients(
                    messageID:
                        second.parsed.message
                        .messageID
                )

            #expect(
                secondRecipients.count == 1
            )
            #expect(
                secondRecipients.first?.type
                    == RecipientType
                    .to
                    .rawValue
            )
        } catch {
            try? await fixture.remove()
            throw error
        }

        try await fixture.remove()
    }
}

@Test(
    "Last occurrence of a Message-ID supplies final recipients"
)
func lastMessageOccurrenceWins() async throws {
    try await withApp(
        configure: configure
    ) { app in
        let fixture = try await DatabaseFixture(
            app: app
        )

        do {
            let messageID =
                "\(fixture.prefix)-duplicate@example.com"

            let oldEmail =
                "\(fixture.prefix)-old@example.com"

            let newEmail =
                "\(fixture.prefix)-new@example.com"

            let first = try fixture.message(
                number: 1,
                messageID: messageID,
                to: [
                    "Old Recipient <\(oldEmail)>"
                ]
            )

            let second = try fixture.message(
                number: 2,
                messageID: messageID,
                cc: [
                    "New Recipient <\(newEmail)>"
                ]
            )

            _ = try await PostgresIngestService(
                client: app.postgres
            ).ingestBatch(
                [first, second],
                mailingListID:
                    fixture.mailingListID,
                epoch: fixture.epoch,
                expectedPreviousCommitOID: nil,
                logger: app.logger
            )

            let recipients =
                try await fixture.recipients(
                    messageID: messageID
                )

            #expect(recipients.count == 1)
            #expect(
                recipients.first?.email
                    == newEmail.lowercased()
            )
            #expect(
                recipients.first?.type
                    == RecipientType
                    .cc
                    .rawValue
            )
        } catch {
            try? await fixture.remove()
            throw error
        }

        try await fixture.remove()
    }
}

@Test(
    "Last empty recipient set removes previous links"
)
func emptyRecipientSetRemovesLinks() async throws {
    try await withApp(
        configure: configure
    ) { app in
        let fixture = try await DatabaseFixture(
            app: app
        )

        do {
            let messageID =
                "\(fixture.prefix)-empty@example.com"

            let recipientEmail =
                "\(fixture.prefix)-removed@example.com"

            let first = try fixture.message(
                number: 1,
                messageID: messageID,
                to: [
                    "Removed <\(recipientEmail)>"
                ]
            )

            let second = try fixture.message(
                number: 2,
                messageID: messageID
            )

            _ = try await PostgresIngestService(
                client: app.postgres
            ).ingestBatch(
                [first, second],
                mailingListID:
                    fixture.mailingListID,
                epoch: fixture.epoch,
                expectedPreviousCommitOID: nil,
                logger: app.logger
            )

            #expect(
                try await fixture.recipients(
                    messageID: messageID
                ).isEmpty
            )
        } catch {
            try? await fixture.remove()
            throw error
        }

        try await fixture.remove()
    }
}

@Test(
    "Reply before parent replaces placeholder in one thread"
)
func resolvesPlaceholderInBatch() async throws {
    try await withApp(
        configure: configure
    ) { app in
        let fixture = try await DatabaseFixture(
            app: app
        )

        do {
            let rootMessageID =
                "\(fixture.prefix)-root@example.com"

            let replyMessageID =
                "\(fixture.prefix)-reply@example.com"

            let reply = try fixture.message(
                number: 1,
                messageID: replyMessageID,
                inReplyTo: rootMessageID
            )

            let root = try fixture.message(
                number: 2,
                messageID: rootMessageID
            )

            _ = try await PostgresIngestService(
                client: app.postgres
            ).ingestBatch(
                [reply, root],
                mailingListID:
                    fixture.mailingListID,
                epoch: fixture.epoch,
                expectedPreviousCommitOID: nil,
                logger: app.logger
            )

            let rootState =
                try #require(
                    try await fixture.messageState(
                        messageID:
                            rootMessageID
                    )
                )

            let replyState =
                try #require(
                    try await fixture.messageState(
                        messageID:
                            replyMessageID
                    )
                )

            #expect(
                rootState.threadID
                    == replyState.threadID
            )
            #expect(!rootState.isPlaceholder)
            #expect(
                try await fixture.threadCount()
                    == 1
            )
        } catch {
            try? await fixture.remove()
            throw error
        }

        try await fixture.remove()
    }
}

@Test(
    "Thread merge remaps cached message state"
)
func remapsCachedThreadAfterMerge() async throws {
    try await withApp(
        configure: configure
    ) { app in
        let fixture = try await DatabaseFixture(
            app: app
        )

        do {
            let messageA =
                "\(fixture.prefix)-a@example.com"

            let messageB =
                "\(fixture.prefix)-b@example.com"

            let messageC =
                "\(fixture.prefix)-c@example.com"

            let root =
                "\(fixture.prefix)-root@example.com"

            let initialA = try fixture.message(
                number: 1,
                messageID: messageA
            )

            let b = try fixture.message(
                number: 2,
                messageID: messageB,
                inReplyTo: root
            )

            let movedA = try fixture.message(
                number: 3,
                messageID: messageA,
                inReplyTo: messageB
            )

            let c = try fixture.message(
                number: 4,
                messageID: messageC,
                inReplyTo: messageA
            )

            _ = try await PostgresIngestService(
                client: app.postgres
            ).ingestBatch(
                [
                    initialA,
                    b,
                    movedA,
                    c,
                ],
                mailingListID:
                    fixture.mailingListID,
                epoch: fixture.epoch,
                expectedPreviousCommitOID: nil,
                logger: app.logger
            )

            let aState = try #require(
                try await fixture.messageState(
                    messageID: messageA
                )
            )

            let bState = try #require(
                try await fixture.messageState(
                    messageID: messageB
                )
            )

            let cState = try #require(
                try await fixture.messageState(
                    messageID: messageC
                )
            )

            #expect(
                aState.threadID
                    == bState.threadID
            )
            #expect(
                bState.threadID
                    == cState.threadID
            )
            #expect(
                try await fixture.threadCount()
                    == 1
            )
        } catch {
            try? await fixture.remove()
            throw error
        }

        try await fixture.remove()
    }
}

@Test(
    "Batch preserves association and thread metadata ordering"
)
func batchesAssociationsAndThreadMetadata()
    async throws
{
    try await withApp(
        configure: configure
    ) { app in
        let fixture = try await DatabaseFixture(
            app: app
        )

        do {
            let rootMessageID =
                "\(fixture.prefix)-metadata-root@example.com"

            let replyMessageID =
                "\(fixture.prefix)-metadata-reply@example.com"

            let firstRoot = try fixture.message(
                number: 1,
                messageID: rootMessageID,
                subject: "Initial root subject",
                dateHeader:
                    "Tue, 18 Aug 2026 10:00:00 -0400"
            )

            let reply = try fixture.message(
                number: 2,
                messageID: replyMessageID,
                inReplyTo: rootMessageID,
                subject: "Later reply subject",
                dateHeader:
                    "Tue, 18 Aug 2026 14:00:00 -0400"
            )

            let finalRoot = try fixture.message(
                number: 3,
                messageID: rootMessageID,
                subject: "Final root subject",
                dateHeader:
                    "Tue, 18 Aug 2026 12:00:00 -0400"
            )

            _ = try await PostgresIngestService(
                client: app.postgres
            ).ingestBatch(
                [
                    firstRoot,
                    reply,
                    finalRoot,
                ],
                mailingListID:
                    fixture.mailingListID,
                epoch: fixture.epoch,
                expectedPreviousCommitOID: nil,
                logger: app.logger
            )

            #expect(
                try await fixture
                    .mailingListBlobOID(
                        messageID:
                            rootMessageID
                    )
                    == finalRoot.blobOID
            )

            #expect(
                try await fixture
                    .mailingListBlobOID(
                        messageID:
                            replyMessageID
                    )
                    == reply.blobOID
            )

            let metadata = try #require(
                try await fixture.threadMetadata(
                    messageID: rootMessageID
                )
            )

            #expect(
                metadata.subject
                    == "Final root subject"
            )

            let replyDate = try #require(
                reply.parsed.message.date
            )

            #expect(
                metadata.lastUpdatedAt
                    == replyDate
            )
        } catch {
            try? await fixture.remove()
            throw error
        }

        try await fixture.remove()
    }
}
