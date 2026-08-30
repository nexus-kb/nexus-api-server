@testable import NexusKb
import Foundation
import PostgresNIO
import Vapor
import VaporTesting
import Testing

@Suite("BM25 thread search API integration tests")
struct SearchAPIIntegrationTests {
    @Test("Search ranks threads and uses only the first two reply levels")
    func searchesThreadDocuments() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = try await SearchFixture(
                app: app
            )

            do {
                try await app.testing().test(
                    .GET,
                    searchPath(
                        query: fixture.searchToken,
                        limit: 10
                    )
                ) { response async throws in
                    #expect(response.status == .ok)
                    let value = try response.content.decode(
                        MailSearchCollectionView.self
                    )
                    let result = try #require(
                        value.items.first {
                            $0.rootMessageId
                                == fixture.rootMessageID
                        }
                    )

                    #expect(result.score > 0)
                    #expect(result.messageCount == 4)
                    #expect(
                        result.snippet.lowercased()
                            .contains(
                                fixture.searchToken
                                    .lowercased()
                            )
                    )
                    #expect(
                        value.items.contains {
                            $0.rootMessageId
                                == fixture.secondRootMessageID
                        }
                    )
                }

                for excludedToken in [
                    fixture.quotedToken,
                    fixture.diffToken,
                    fixture.deepReplyToken,
                ] {
                    try await app.testing().test(
                        .GET,
                        searchPath(
                            query: excludedToken,
                            limit: 10
                        )
                    ) { response async throws in
                        #expect(response.status == .ok)
                        let value = try response.content.decode(
                            MailSearchCollectionView.self
                        )
                        #expect(value.items.isEmpty)
                    }
                }

                try await app.testing().test(
                    .GET,
                    searchPath(
                        query:
                            "subject:\(fixture.subjectToken)",
                        limit: 10
                    )
                ) { response async throws in
                    #expect(response.status == .ok)
                    let value = try response.content.decode(
                        MailSearchCollectionView.self
                    )
                    #expect(value.items.count == 1)
                    #expect(
                        value.items.first?.rootMessageId
                            == fixture.rootMessageID
                    )
                    #expect(
                        value.items.first?.score ?? 0 > 0
                    )
                }

                try await app.testing().test(
                    .GET,
                    searchPath(
                        query:
                            "\(fixture.searchToken) subject:\(fixture.subjectToken) author:\(fixture.authorToken) date:2026-08-15",
                        limit: 10
                    )
                ) { response async throws in
                    #expect(response.status == .ok)
                    let value = try response.content.decode(
                        MailSearchCollectionView.self
                    )
                    #expect(value.items.count == 1)
                    #expect(
                        value.items.first?.rootMessageId
                            == fixture.rootMessageID
                    )
                }

                for rootOnlyFilter in [
                    "\(fixture.searchToken) author:\(fixture.childAuthorToken)",
                    "subject:\(fixture.childSubjectToken)",
                    "\(fixture.searchToken) author:\(fixture.authorToken) date:2026-08-16",
                ] {
                    try await app.testing().test(
                        .GET,
                        searchPath(
                            query: rootOnlyFilter,
                            limit: 10
                        )
                    ) { response async throws in
                        #expect(response.status == .ok)
                        let value = try response.content.decode(
                            MailSearchCollectionView.self
                        )
                        #expect(value.items.isEmpty)
                    }
                }

                try await app.testing().test(
                    .GET,
                    searchPath(
                        query:
                            "author:\(fixture.authorToken) date:2026-08-15",
                        limit: 10
                    )
                ) { response async throws in
                    #expect(response.status == .ok)
                    let value = try response.content.decode(
                        MailSearchCollectionView.self
                    )
                    #expect(value.items.count == 1)
                    #expect(
                        value.items.first?.rootMessageId
                            == fixture.rootMessageID
                    )
                    #expect(value.items.first?.score == 0)
                }

                var firstPage: MailSearchCollectionView?

                try await app.testing().test(
                    .GET,
                    searchPath(
                        query: fixture.searchToken,
                        limit: 1
                    )
                ) { response async throws in
                    #expect(response.status == .ok)
                    firstPage = try response.content.decode(
                        MailSearchCollectionView.self
                    )
                    #expect(firstPage?.items.count == 1)
                    #expect(
                        firstPage?.pagination.nextCursor
                            != nil
                    )
                }

                let nextCursor = try #require(
                    firstPage?.pagination.nextCursor
                )

                try await app.testing().test(
                    .GET,
                    searchPath(cursor: nextCursor)
                ) { response async throws in
                    #expect(response.status == .ok)
                    let value = try response.content.decode(
                        MailSearchCollectionView.self
                    )
                    #expect(value.items.count == 1)
                    #expect(
                        value.items.first?.rootMessageId
                            != firstPage?.items.first?
                                .rootMessageId
                    )
                    #expect(
                        value.pagination.previousCursor
                            != nil
                    )
                }

                try await app.testing().test(
                    .GET,
                    searchPath(
                        query: fixture.deepReplyToken,
                        cursor: nextCursor
                    )
                ) { response async throws in
                    #expect(response.status == .badRequest)
                }

                let firstCount = try await fixture.refresh()
                let secondCount = try await fixture.refresh()
                #expect(firstCount == secondCount)
                #expect(firstCount == 1)
            } catch {
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }
}

private final class SearchFixture {
    let app: Application
    let threadID: Int64
    let secondThreadID: Int64
    let rootMessageID: String
    let secondRootMessageID: String
    let searchToken: String
    let quotedToken: String
    let diffToken: String
    let deepReplyToken: String
    let subjectToken: String
    let childSubjectToken: String
    let authorToken: String
    let childAuthorToken: String

    init(app: Application) async throws {
        self.app = app
        let suffix = UUID().uuidString
            .replacingOccurrences(
                of: "-",
                with: ""
            )
            .lowercased()
        self.rootMessageID =
            "thread-search-\(suffix)@example.com"
        self.secondRootMessageID =
            "thread-search-second-\(suffix)@example.com"
        self.searchToken = "threadtext\(suffix)"
        self.quotedToken = "quotedtext\(suffix)"
        self.diffToken = "difftext\(suffix)"
        self.deepReplyToken = "deepreply\(suffix)"
        self.subjectToken = "rootsubject\(suffix)"
        self.childSubjectToken =
            "childsubject\(suffix)"
        self.authorToken = "rootauthor\(suffix)"
        self.childAuthorToken =
            "childauthor\(suffix)"
        let rows = try await app.postgres.query(
            """
            INSERT INTO threads (
                root_message_id,
                subject,
                last_updated_at
            )
            VALUES
                (
                    \(rootMessageID),
                    \("Thread search \(subjectToken)"),
                    '2026-08-18 12:00:00+00'
                ),
                (
                    \(secondRootMessageID),
                    'Thread search pagination fixture',
                    '2026-08-14 12:00:00+00'
                )
            RETURNING id, root_message_id
            """,
            logger: app.logger
        )
        var insertedThreadID: Int64?
        var insertedSecondThreadID: Int64?

        for try await row in rows {
            let cells = Array(row)
            let rootMessageID = try cells[1]
                .decode(String.self)

            if rootMessageID == self.rootMessageID {
                insertedThreadID = try cells[0]
                    .decode(Int64.self)
            } else {
                insertedSecondThreadID = try cells[0]
                    .decode(Int64.self)
            }
        }

        self.threadID = try #require(
            insertedThreadID
        )
        self.secondThreadID = try #require(
            insertedSecondThreadID
        )
        let firstReplyID =
            "thread-search-reply-1-\(suffix)@example.com"
        let secondReplyID =
            "thread-search-reply-2-\(suffix)@example.com"
        let thirdReplyID =
            "thread-search-reply-3-\(suffix)@example.com"
        let messageRows = try await app.postgres.query(
            """
            INSERT INTO messages (
                message_id,
                thread_id,
                in_reply_to,
                author,
                subject,
                sent_at,
                body
            )
            VALUES
                (
                    \(rootMessageID),
                    \(threadID),
                    NULL,
                    \("Search Root \(authorToken) <root@example.com>"),
                    \("Thread search \(subjectToken)"),
                    '2026-08-15 12:00:00+00',
                    'Cover letter overview.'
                ),
                (
                    \(firstReplyID),
                    \(threadID),
                    \(rootMessageID),
                    \("Search Child \(childAuthorToken) <child@example.com>"),
                    \("Re: \(childSubjectToken)"),
                    '2026-08-16 12:00:00+00',
                    \("First discussion level.\n> Copied parent \(quotedToken).\n\ndiff --git a/test.c b/test.c\n+\(diffToken)")
                ),
                (
                    \(secondReplyID),
                    \(threadID),
                    \(firstReplyID),
                    'Second-level Participant <level-two@example.com>',
                    'Re: second discussion level',
                    '2026-08-17 12:00:00+00',
                    \("Second discussion level contains \(searchToken).")
                ),
                (
                    \(thirdReplyID),
                    \(threadID),
                    \(secondReplyID),
                    'Third-level Participant <level-three@example.com>',
                    'Re: third discussion level',
                    '2026-08-18 12:00:00+00',
                    \("Third discussion level contains \(deepReplyToken).")
                ),
                (
                    \(secondRootMessageID),
                    \(secondThreadID),
                    NULL,
                    'Other Root <other-root@example.com>',
                    'Thread search pagination fixture',
                    '2026-08-14 12:00:00+00',
                    \("Another thread contains \(searchToken).")
                )
            """,
            logger: app.logger
        )

        for try await _ in messageRows {}
    }

    func refresh() async throws -> Int64 {
        let rows = try await app.postgres.query(
            """
            SELECT refresh_thread_search_documents(
                ARRAY[\(threadID)]::bigint[]
            )
            """,
            logger: app.logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        return 0
    }

    func remove() async throws {
        let rows = try await app.postgres.query(
            """
            DELETE FROM threads
            WHERE id IN (
                \(threadID),
                \(secondThreadID)
            )
            """,
            logger: app.logger
        )

        for try await _ in rows {}
    }
}

private func searchPath(
    query: String? = nil,
    cursor: String? = nil,
    limit: Int? = nil
) -> String {
    var components = URLComponents()
    components.path = "/api/v1/search"
    components.queryItems = [
        query.map {
            URLQueryItem(name: "q", value: $0)
        },
        cursor.map {
            URLQueryItem(name: "cursor", value: $0)
        },
        limit.map {
            URLQueryItem(
                name: "limit",
                value: String($0)
            )
        },
    ].compactMap { $0 }

    return components.string!
}
