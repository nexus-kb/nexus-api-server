import Foundation

enum PageDirection:
    String,
    Codable,
    Sendable
{
    case previous
    case next
}

enum ThreadKind:
    String,
    Codable,
    Sendable
{
    case patchSeries = "patch-series"
    case discussion
}

struct ThreadPageScope:
    Codable,
    Sendable,
    Equatable
{
    let limit: Int
    let mailingList: String?
    let subsystem: String?
    let kind: ThreadKind?
}

struct ThreadCursor:
    Codable,
    Sendable
{
    let version: Int
    let direction: PageDirection
    let anchorUpdatedAtMicroseconds: Int64
    let anchorRootMessageID: String
    let scope: ThreadPageScope

    var anchorUpdatedAt: Date {
        Date(
            timeIntervalSince1970:
                Double(anchorUpdatedAtMicroseconds)
                / 1_000_000
        )
    }
}

struct MessageCursor:
    Codable,
    Sendable
{
    let version: Int
    let direction: PageDirection
    let rootMessageID: String
    let anchorSortAtMicroseconds: Int64
    let anchorMessageID: String
    let limit: Int

    var anchorSortAt: Date {
        Date(
            timeIntervalSince1970:
                Double(anchorSortAtMicroseconds)
                / 1_000_000
        )
    }
}

enum PaginationCursorError:
    Error,
    Sendable
{
    case malformed
    case unsupportedVersion
}

enum PaginationCursorCodec {
    static func encode<T: Encodable>(
        _ cursor: T
    ) throws -> String {
        let data = try JSONEncoder().encode(cursor)

        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeThread(
        _ value: String
    ) throws -> ThreadCursor {
        let cursor: ThreadCursor = try decode(value)

        guard cursor.version == 1 else {
            throw PaginationCursorError.unsupportedVersion
        }

        return cursor
    }

    static func decodeMessage(
        _ value: String
    ) throws -> MessageCursor {
        let cursor: MessageCursor = try decode(value)

        guard cursor.version == 1 else {
            throw PaginationCursorError.unsupportedVersion
        }

        return cursor
    }

    static func decodeMailSearch(
        _ value: String
    ) throws -> MailSearchCursor {
        let cursor: MailSearchCursor = try decode(
            value
        )

        guard cursor.version == 1,
              cursor.offset >= 0
        else {
            throw PaginationCursorError
                .unsupportedVersion
        }

        return cursor
    }

    private static func decode<T: Decodable>(
        _ value: String
    ) throws -> T {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4

        if remainder != 0 {
            base64.append(
                String(
                    repeating: "=",
                    count: 4 - remainder
                )
            )
        }

        guard let data = Data(base64Encoded: base64) else {
            throw PaginationCursorError.malformed
        }

        do {
            return try JSONDecoder().decode(
                T.self,
                from: data
            )
        } catch {
            throw PaginationCursorError.malformed
        }
    }
}

extension Date {
    var postgresMicrosecondsSince1970: Int64 {
        Int64(
            (
                timeIntervalSince1970
                * 1_000_000
            ).rounded()
        )
    }
}
