@testable import NexusKb
import Foundation
import Testing

@Suite("Read API model tests")
struct ReadAPIModelTests {
    @Test("Mail search parses text and selectors")
    func mailSearchParsesSelectors() throws {
        let parsed = try MailSearchParser.parse(
            "RCU net: subject:\"memory ordering\" author:\"Paul E. McKenney\" date:2026-08-01..2026-08-20"
        )
        let search = try #require(parsed)

        #expect(search.text == "RCU net:")
        #expect(search.subject == "\"memory ordering\"")
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

    @Test("Mail search preserves unscoped query syntax")
    func mailSearchPreservesTextSyntax() throws {
        let parsed = try MailSearchParser.parse(
            "\"memory ordering\" drm: -regression"
        )
        let search = try #require(parsed)

        #expect(
            search.text
                == "\"memory ordering\" drm: -regression"
        )
        #expect(search.subject == nil)
        #expect(search.author == nil)
        #expect(search.sentAtLowerBound == nil)
        #expect(search.sentAtUpperBound == nil)
    }

    @Test("Mail search parses exact and open dates")
    func mailSearchParsesDateBounds() throws {
        let parsedExact = try MailSearchParser.parse(
            "date:2026-08-20"
        )
        let parsedLowerOpen = try MailSearchParser.parse(
            "date:..2026-08-20"
        )
        let parsedUpperOpen = try MailSearchParser.parse(
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
        "Mail search rejects malformed queries",
        arguments: [
            "subject:",
            "subject:\" \"",
            "subject:one subject:two",
            "author:",
            "author:\" \"",
            "author:one author:two",
            "date:2026-02-30",
            "date:2026-08-20..2026-08-01",
            "\"unterminated",
        ]
    )
    func mailSearchRejectsMalformedQuery(
        query: String
    ) {
        #expect(throws: MailSearchParseError.self) {
            try MailSearchParser.parse(query)
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
                kind: .patchSeries
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

    @Test("Mail search cursors round trip their normalized scope")
    func mailSearchCursorRoundTrip() throws {
        let cursor = MailSearchCursor(
            version: 1,
            offset: 50,
            scope: MailSearchScope(
                limit: 25,
                mailingList: "linux-kernel",
                filter: MailSearchFilter(
                    text: "scheduler",
                    subject: "\"grace period\"",
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
            .decodeMailSearch(encoded)

        #expect(decoded.offset == cursor.offset)
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
                kind: nil
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
