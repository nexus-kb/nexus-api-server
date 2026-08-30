@testable import NexusKb
import Foundation
import PostgresNIO
import Vapor
import VaporTesting
import Testing

@Suite("Read API integration tests")
struct ReadAPIIntegrationTests {
    @Test("Read endpoints execute against Postgres")
    func readEndpoints() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture =
                try await ReadAPIIntegrationFixture(
                    app: app
                )

            do {
            var firstThread: ThreadSummaryView?
            var firstPage: ThreadListView?
            var firstMessage: MessageDetailView?

            try await app.testing().test(
                .GET,
                "/api/v1/threads?limit=1"
            ) { response async throws in
                #expect(response.status == .ok)
                let value = try response.content.decode(
                    ThreadListView.self
                )
                #expect(value.items.count <= 1)
                firstThread = value.items.first
                firstPage = value
            }

            try await app.testing().test(
                .GET,
                "/api/v1/threads?q=\(fixture.searchToken)"
            ) { response async throws in
                #expect(response.status == .badRequest)
                #expect(
                    response.body.string.contains(
                        "Thread search moved"
                    )
                )
            }

            if let firstPage,
               let nextCursor =
                    firstPage.pagination.nextCursor
            {
                var nextPage: ThreadListView?

                try await app.testing().test(
                    .GET,
                    "/api/v1/threads?cursor=\(nextCursor)"
                ) { response async throws in
                    #expect(response.status == .ok)
                    let value = try response.content.decode(
                        ThreadListView.self
                    )
                    #expect(
                        value.pagination.previousCursor
                            != nil
                    )
                    nextPage = value
                }

                if let previousCursor =
                    nextPage?.pagination.previousCursor
                {
                    try await app.testing().test(
                        .GET,
                        "/api/v1/threads?cursor=\(previousCursor)"
                    ) { response async throws in
                        #expect(response.status == .ok)
                        let value = try response.content.decode(
                            ThreadListView.self
                        )
                        #expect(
                            value.items.first?.rootMessageId
                                == firstPage.items.first?
                                    .rootMessageId
                        )
                    }
                }
            }

            try await app.testing().test(
                .GET,
                "/api/v1/mailing-lists"
            ) { response async throws in
                #expect(response.status == .ok)
                _ = try response.content.decode(
                    MailingListCollectionView.self
                )
            }

            try await app.testing().test(
                .GET,
                "/api/v1/subsystems"
            ) { response async throws in
                #expect(response.status == .ok)
                _ = try response.content.decode(
                    SubsystemCollectionView.self
                )
            }

            let requiredThread = try #require(
                firstThread
            )
            #expect(
                requiredThread.rootMessageId
                    == fixture.rootMessageID
            )

            let encoded = try #require(
                requiredThread.rootMessageId
                    .addingPercentEncoding(
                        withAllowedCharacters:
                            .readAPIPathAllowed
                    )
            )

            try await app.testing().test(
                .GET,
                "/api/v1/threads/\(encoded)"
            ) { response async throws in
                #expect(response.status == .ok)
                let value = try response.content.decode(
                    ThreadDetailView.self
                )
                #expect(
                    value.rootMessageId
                        == requiredThread.rootMessageId
                )
            }

            try await app.testing().test(
                .GET,
                "/api/v1/threads/\(encoded)/messages?limit=1"
            ) { response async throws in
                #expect(response.status == .ok)
                let value = try response.content.decode(
                    ThreadMessagesView.self
                )
                #expect(value.items.count <= 1)
                firstMessage = value.items.first
                #expect(
                    firstMessage?.body
                        == "Fixture body"
                )
            }

            if let firstMessage {
                let encodedMessage = try #require(
                    firstMessage.messageId
                        .addingPercentEncoding(
                            withAllowedCharacters:
                                .readAPIPathAllowed
                        )
                )

                try await app.testing().test(
                    .GET,
                    "/api/v1/messages/\(encodedMessage)"
                ) { response async throws in
                    #expect(response.status == .ok)
                    let value = try response.content.decode(
                        MessageDetailView.self
                    )
                    #expect(
                        value.messageId
                            == firstMessage.messageId
                    )
                    #expect(
                        value.rootMessageId
                            == requiredThread.rootMessageId
                    )
                }
            }
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }
}

private final class ReadAPIIntegrationFixture {
    let app: Application
    let rootMessageID: String
    let searchToken: String
    let threadID: Int64
    let companionThreadID: Int64

    init(app: Application) async throws {
        self.app = app
        self.rootMessageID =
            "read-api-\(UUID().uuidString)@example.com"
        self.searchToken =
            "readapi\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let sentAt = Date(
            timeIntervalSince1970:
                4_102_444_800
        )
        let rows = try await app.postgres.query(
            """
            INSERT INTO threads (
                root_message_id,
                subject,
                last_updated_at
            )
            VALUES (
                \(rootMessageID),
                \(searchToken),
                \(sentAt)
            )
            RETURNING id
            """,
            logger: app.logger
        )
        var insertedThreadID: Int64?

        for try await row in rows {
            insertedThreadID = try row.decode(
                Int64.self
            )
        }

        self.threadID = try #require(
            insertedThreadID
        )
        let companionRootMessageID =
            "read-api-companion-\(UUID().uuidString)@example.com"
        let companionSentAt = sentAt.addingTimeInterval(
            -1
        )
        let companionRows = try await app.postgres.query(
            """
            INSERT INTO threads (
                root_message_id,
                subject,
                last_updated_at
            )
            VALUES (
                \(companionRootMessageID),
                \(searchToken),
                \(companionSentAt)
            )
            RETURNING id
            """,
            logger: app.logger
        )
        var insertedCompanionThreadID: Int64?

        for try await row in companionRows {
            insertedCompanionThreadID = try row.decode(
                Int64.self
            )
        }

        self.companionThreadID = try #require(
            insertedCompanionThreadID
        )
        let messageRows = try await app.postgres.query(
            """
            INSERT INTO messages (
                message_id,
                thread_id,
                author,
                subject,
                sent_at,
                body
            )
            VALUES (
                \(rootMessageID),
                \(threadID),
                'Read API <read-api@example.com>',
                \(searchToken),
                \(sentAt),
                'Fixture body'
            ),
            (
                \(companionRootMessageID),
                \(companionThreadID),
                'Read API <read-api@example.com>',
                \(searchToken),
                \(companionSentAt),
                'Companion fixture body'
            )
            """,
            logger: app.logger
        )

        for try await _ in messageRows {}
    }

    func remove() async throws {
        let rows = try await app.postgres.query(
            """
            DELETE FROM threads
            WHERE id IN (
                \(threadID),
                \(companionThreadID)
            )
            """,
            logger: app.logger
        )

        for try await _ in rows {}
    }
}

private extension CharacterSet {
    static var readAPIPathAllowed: CharacterSet {
        var value = CharacterSet.urlPathAllowed
        value.remove(charactersIn: "/?#%")
        return value
    }
}
