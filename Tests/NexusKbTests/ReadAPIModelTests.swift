@testable import NexusKb
import Foundation
import Testing

@Suite("Read API model tests")
struct ReadAPIModelTests {
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
