@testable import NexusKb
import Foundation
import Testing

@Suite("Read API model tests")
struct ReadAPIModelTests {
    @Test("Thread search parses subject and selectors")
    func threadSearchParsesSelectors() throws {
        let parsed = try ThreadSearchParser.parse(
            "RCU net: author:\"Paul E. McKenney\" date:2026-08-01..2026-08-20"
        )
        let search = try #require(parsed)

        #expect(search.subject == "RCU net:")
        #expect(search.author == "Paul E. McKenney")
        #expect(
            search.sentAtLowerBound
                == utcDate(
                    year: 2026,
                    month: 8,
                    day: 1
                )
        )
        #expect(
            search.sentAtUpperBound
                == utcDate(
                    year: 2026,
                    month: 8,
                    day: 21
                )
        )
    }

    @Test("Thread search preserves subject syntax")
    func threadSearchPreservesSubjectSyntax() throws {
        let parsed = try ThreadSearchParser.parse(
            "\"memory ordering\" drm: -regression"
        )
        let search = try #require(parsed)

        #expect(
            search.subject
                == "\"memory ordering\" drm: -regression"
        )
        #expect(search.author == nil)
        #expect(search.sentAtLowerBound == nil)
        #expect(search.sentAtUpperBound == nil)
    }

    @Test("Thread search parses exact and open dates")
    func threadSearchParsesDateBounds() throws {
        let parsedExact = try ThreadSearchParser.parse(
            "date:2026-08-20"
        )
        let parsedLowerOpen = try ThreadSearchParser.parse(
            "date:..2026-08-20"
        )
        let parsedUpperOpen = try ThreadSearchParser.parse(
            "date:2026-08-20.."
        )
        let exact = try #require(parsedExact)
        let lowerOpen = try #require(parsedLowerOpen)
        let upperOpen = try #require(parsedUpperOpen)

        #expect(
            exact.sentAtLowerBound
                == utcDate(
                    year: 2026,
                    month: 8,
                    day: 20
                )
        )
        #expect(
            exact.sentAtUpperBound
                == utcDate(
                    year: 2026,
                    month: 8,
                    day: 21
                )
        )
        #expect(lowerOpen.sentAtLowerBound == nil)
        #expect(
            lowerOpen.sentAtUpperBound
                == exact.sentAtUpperBound
        )
        #expect(
            upperOpen.sentAtLowerBound
                == exact.sentAtLowerBound
        )
        #expect(upperOpen.sentAtUpperBound == nil)
    }

    @Test(
        "Thread search rejects malformed queries",
        arguments: [
            "author:",
            "author:\" \"",
            "author:one author:two",
            "date:2026-02-30",
            "date:2026-08-20..2026-08-01",
            "\"unterminated",
        ]
    )
    func threadSearchRejectsMalformedQuery(
        query: String
    ) {
        #expect(throws: ThreadSearchParseError.self) {
            try ThreadSearchParser.parse(query)
        }
    }

    @Test("Message identifiers remove one bracket pair")
    func bracketedMessageIdentifier() throws {
        let value = try MessageIdentifier(
            "<message/example?value#fragment%@example.com>"
        )

        #expect(
            value.value
                == "message/example?value#fragment%@example.com"
        )
    }

    @Test(
        "Message identifiers reject malformed values",
        arguments: [
            "",
            "message id@example.com",
            "<message@example.com",
            "message@example.com>",
        ]
    )
    func invalidMessageIdentifier(
        value: String
    ) {
        #expect(throws: MessageIdentifierError.self) {
            try MessageIdentifier(value)
        }
    }

    @Test("Thread cursors round trip their scope")
    func threadCursorRoundTrip() throws {
        let cursor = ThreadCursor(
            version: 1,
            direction: .previous,
            anchorUpdatedAtMicroseconds:
                1_787_000_123_456_789,
            anchorRootMessageID:
                "root/message@example.com",
            scope: ThreadPageScope(
                limit: 25,
                mailingList: "lkml",
                subsystem: "Networking",
                kind: .patchSeries,
                search: ThreadSearch(
                    subject: "scheduler",
                    author: "torvalds",
                    sentAtLowerBound: Date(
                        timeIntervalSince1970:
                            1_787_097_600
                    ),
                    sentAtUpperBound: Date(
                        timeIntervalSince1970:
                            1_787_184_000
                    )
                )
            )
        )

        let encoded = try PaginationCursorCodec
            .encode(cursor)
        let decoded = try PaginationCursorCodec
            .decodeThread(encoded)

        #expect(decoded.direction == .previous)
        #expect(
            decoded.anchorUpdatedAtMicroseconds
                == cursor.anchorUpdatedAtMicroseconds
        )
        #expect(
            decoded.anchorRootMessageID
                == cursor.anchorRootMessageID
        )
        #expect(decoded.scope == cursor.scope)
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(!encoded.contains("="))
    }

    @Test("Message cursors round trip")
    func messageCursorRoundTrip() throws {
        let cursor = MessageCursor(
            version: 1,
            direction: .next,
            rootMessageID: "root@example.com",
            anchorSortAtMicroseconds:
                1_787_000_123_456_789,
            anchorMessageID:
                "message/example@example.com",
            limit: 100
        )

        let encoded = try PaginationCursorCodec
            .encode(cursor)
        let decoded = try PaginationCursorCodec
            .decodeMessage(encoded)

        #expect(decoded.direction == .next)
        #expect(
            decoded.rootMessageID
                == cursor.rootMessageID
        )
        #expect(
            decoded.anchorMessageID
                == cursor.anchorMessageID
        )
        #expect(decoded.limit == cursor.limit)
    }

    @Test("Unsupported cursor versions are rejected")
    func unsupportedCursorVersion() throws {
        let cursor = ThreadCursor(
            version: 2,
            direction: .next,
            anchorUpdatedAtMicroseconds: 0,
            anchorRootMessageID: "root@example.com",
            scope: ThreadPageScope(
                limit: 25,
                mailingList: nil,
                subsystem: nil,
                kind: nil,
                search: nil
            )
        )

        let encoded = try PaginationCursorCodec
            .encode(cursor)

        #expect(throws: PaginationCursorError.self) {
            try PaginationCursorCodec
                .decodeThread(encoded)
        }
    }
}

private func utcDate(
    year: Int,
    month: Int,
    day: Int
) -> Date {
    var calendar = Calendar(
        identifier: .gregorian
    )
    calendar.timeZone = TimeZone(
        secondsFromGMT: 0
    )!

    return calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day
        )
    )!
}
