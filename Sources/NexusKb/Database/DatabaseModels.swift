//
//  DatabaseModels.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/11/26.
//

import Foundation

struct MailingListRecord: Sendable {
    let id: Int64
    let name: String
    let archiveGroup: String
    let archivePath: String?
    let createdAt: Date
    let updatedAt: Date
}

struct MailingListArchiveEpochRecord: Sendable {
    let id: Int64
    let mailingListID: Int64
    let epoch: Int32
    let lastScannedCommitOID: String?
    let createdAt: Date
    let updatedAt: Date
}

struct DiscussionThreadRecord: Sendable {
    let id: Int64
    let rootMessageID: String
    let subject: String?
    let lastUpdatedAt: Date
    let createdAt: Date
}

struct MessageRecord: Sendable {
    let id: Int64
    let messageID: String
    let threadID: Int64
    let inReplyTo: String?
    let referenceMessageIDs: [String]
    let author: String?
    let subject: String?
    let sentAt: Date?
    let body: String
    let toRecipients: String
    let ccRecipients: String
    let isPlaceholder: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct MessageMailingListRecord: Sendable {
    let messageID: Int64
    let mailingListID: Int64
    let archiveBlobOID: String?
    let firstSeenAt: Date
}

struct PersonRecord: Sendable {
    let id: Int64
    let name: String?
    let email: String
    let createdAt: Date
}

enum RecipientType: String, Sendable {
    case to = "To"
    case cc = "Cc"
}

struct MessageRecipientRecord: Sendable {
    let messageID: Int64
    let personID: Int64
    let recipientType: RecipientType
}

enum PatchSetStatus: String, Sendable {
    case incomplete = "Incomplete"
    case complete = "Complete"
    case malformed = "Malformed"
}

struct PatchSetRecord: Sendable {
    let id: Int64
    let threadID: Int64
    let coverLetterMessageID: String?
    let subject: String?
    let author: String?
    let sentAt: Date?
    let status: PatchSetStatus
    let totalParts: Int32
    let receivedParts: Int32
    let subjectIndex: Int32
    let parserVersion: Int32
    let toRecipients: String
    let ccRecipients: String
    let createdAt: Date
    let updatedAt: Date
}

struct PatchRecord: Sendable {
    let id: Int64
    let patchSetID: Int64
    let messageID: String
    let partIndex: Int32
    let diff: String
    let createdAt: Date
}

struct SubsystemRecord: Sendable {
    let id: Int64
    let name: String
    let mailingListAddress: String?
}

struct MessageSubsystemRecord: Sendable {
    let messageID: Int64
    let subsystemID: Int64
}

struct ThreadSubsystemRecord: Sendable {
    let threadID: Int64
    let subsystemID: Int64
}

struct PatchSetSubsystemRecord: Sendable {
    let patchSetID: Int64
    let subsystemID: Int64
}

struct PatchSubsystemRecord: Sendable {
    let patchID: Int64
    let subsystemID: Int64
}
