import Foundation

struct ThreadListQuery: Decodable, Sendable {
    let cursor: String?
    let limit: Int?
    let mailingList: String?
    let subsystem: String?
    let kind: ThreadKind?
}

struct MessageListQuery: Decodable, Sendable {
    let cursor: String?
    let limit: Int?
}
