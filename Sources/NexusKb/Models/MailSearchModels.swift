import Foundation

struct MailSearchResult: Sendable {
    let thread: ThreadSummary
    let score: Double
    let snippet: String
}

struct MailSearchPageResult: Sendable {
    let items: [MailSearchResult]
    let previousCursor: String?
    let nextCursor: String?
}

struct MailSearchScope:
    Codable,
    Sendable,
    Equatable
{
    let limit: Int
    let mailingList: String?
    let filter: MailSearchFilter
}

struct MailSearchCursor:
    Codable,
    Sendable
{
    let version: Int
    let offset: Int
    let scope: MailSearchScope
}

struct MailSearchQuery: Decodable, Sendable {
    let q: String?
    let mailingList: String?
    let cursor: String?
    let limit: Int?
}
