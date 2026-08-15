import Foundation

struct MailingListSummary: Sendable {
    let name: String
    let archiveGroup: String
}

struct SubsystemSummary: Sendable {
    let name: String
    let mailingListAddress: String?
}

struct PatchSeriesSummary: Sendable {
    let coverLetterMessageID: String?
    let status: String
    let totalParts: Int32
    let receivedParts: Int32
}

struct ThreadSummary: Sendable {
    let rootMessageID: String
    let subject: String?
    let author: String?
    let startedAt: Date?
    let lastActivityAt: Date
    let messageCount: Int64
    let missingMessageCount: Int64
    let mailingLists: [MailingListSummary]
    let subsystems: [SubsystemSummary]
    let patchSeries: [PatchSeriesSummary]

    var kind: ThreadKind {
        patchSeries.isEmpty
        ? .discussion
        : .patchSeries
    }
}

struct ThreadPageResult: Sendable {
    let items: [ThreadSummary]
    let previousCursor: String?
    let nextCursor: String?
}

enum MessageAvailability:
    String,
    Sendable
{
    case available
    case missing
}

struct ThreadMessageSummary: Sendable {
    let messageID: String
    let inReplyToMessageID: String?
    let referenceMessageIDs: [String]
    let availability: MessageAvailability
    let subject: String?
    let author: String?
    let sentAt: Date?
    let bodyPreview: String?
    let patchPartIndex: Int32?
    let patchTotalParts: Int32?
    let sortAt: Date
}

struct ThreadMessagePageResult: Sendable {
    let rootMessageID: String
    let items: [ThreadMessageSummary]
    let previousCursor: String?
    let nextCursor: String?
}

struct MailboxSummary: Sendable {
    let name: String?
    let email: String
}

struct MessageDetail: Sendable {
    let messageID: String
    let rootMessageID: String
    let inReplyToMessageID: String?
    let referenceMessageIDs: [String]
    let availability: MessageAvailability
    let subject: String?
    let author: String?
    let to: [MailboxSummary]
    let cc: [MailboxSummary]
    let sentAt: Date?
    let body: String?
    let patchPartIndex: Int32?
    let patchTotalParts: Int32?
    let mailingLists: [MailingListSummary]
    let subsystems: [SubsystemSummary]
}
