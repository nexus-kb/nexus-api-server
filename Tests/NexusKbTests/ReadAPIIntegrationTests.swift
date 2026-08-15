@testable import NexusKb
import Foundation
import VaporTesting
import Testing

@Suite("Read API integration tests")
struct ReadAPIIntegrationTests {
    @Test("Read endpoints execute against Postgres")
    func readEndpoints() async throws {
        try await withApp(
            configure: configure
        ) { app in
            var firstThread: ThreadSummaryView?
            var firstPage: ThreadListView?
            var firstMessage: ThreadMessageSummaryView?

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

            guard let firstThread else {
                return
            }

            let encoded = try #require(
                firstThread.rootMessageId
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
                        == firstThread.rootMessageId
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
                            == firstThread.rootMessageId
                    )
                }
            }
        }
    }
}

private extension CharacterSet {
    static var readAPIPathAllowed: CharacterSet {
        var value = CharacterSet.urlPathAllowed
        value.remove(charactersIn: "/?#%")
        return value
    }
}
