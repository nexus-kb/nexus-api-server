import Foundation

struct PatchLineageRevisionSummary: Sendable {
    let patchSetID: Int64
    let rootMessageID: String
    let coverLetterMessageID: String?
    let subject: String
    let author: String?
    let sentAt: Date?
    let status: String
    let totalParts: Int32
    let receivedParts: Int32
    let phase: String
    let revision: Int32
    let revisionExplicit: Bool
    let isResend: Bool
    let changeID: String?
    let baseCommit: String?
    let matchSource: String
    let matchConfidence: Int32
    let mailingLists: [MailingListSummary]
}

struct PatchLineageDetail: Sendable {
    let id: Int64
    let subject: String
    let firstSentAt: Date?
    let latestSentAt: Date?
    let revisions: [PatchLineageRevisionSummary]
}
