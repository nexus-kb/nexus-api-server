import Foundation

struct ThreadListQuery: Decodable, Sendable {
    let cursor: String?
    let limit: Int?
    let mailingList: String?
    let subsystem: String?
    let kind: ThreadKind?
    let q: String?
}

struct MessageListQuery: Decodable, Sendable {
    let cursor: String?
    let limit: Int?
}
