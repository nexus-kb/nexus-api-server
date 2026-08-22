import Foundation
import Vapor

struct PaginationView: Content {
    let previousCursor: String?
    let nextCursor: String?
}

struct MailingListView: Content {
    let name: String
    let archiveGroup: String

    init(_ value: MailingListSummary) {
        name = value.name
        archiveGroup = value.archiveGroup
    }
}

struct SubsystemView: Content {
    let name: String
    let mailingListAddress: String?

    init(_ value: SubsystemSummary) {
        name = value.name
        mailingListAddress = value.mailingListAddress
    }
}

struct PatchSeriesView: Content {
    let coverLetterMessageId: String?
    let status: String
    let totalParts: Int32
    let receivedParts: Int32

    init(_ value: PatchSeriesSummary) {
        coverLetterMessageId =
            value.coverLetterMessageID
        status = value.status.lowercased()
        totalParts = value.totalParts
        receivedParts = value.receivedParts
    }
}

struct ThreadSummaryView: Content {
    let rootMessageId: String
    let subject: String?
    let author: String?
    let startedAt: Date?
    let lastActivityAt: Date
    let messageCount: Int64
    let missingMessageCount: Int64
    let kind: ThreadKind
    let mailingLists: [MailingListView]
    let subsystems: [SubsystemView]
    let patchSeries: [PatchSeriesView]

    init(_ value: ThreadSummary) {
        rootMessageId = value.rootMessageID
        subject = value.subject
        author = value.author
        startedAt = value.startedAt
        lastActivityAt = value.lastActivityAt
        messageCount = value.messageCount
        missingMessageCount =
            value.missingMessageCount
        kind = value.kind
        mailingLists = value.mailingLists.map(
            MailingListView.init
        )
        subsystems = value.subsystems.map(
            SubsystemView.init
        )
        patchSeries = value.patchSeries.map(
            PatchSeriesView.init
        )
    }
}

struct ThreadListView: Content {
    let items: [ThreadSummaryView]
    let pagination: PaginationView

    init(_ value: ThreadPageResult) {
        items = value.items.map(
            ThreadSummaryView.init
        )
        pagination = PaginationView(
            previousCursor:
                value.previousCursor,
            nextCursor:
                value.nextCursor
        )
    }
}

struct ThreadDetailView: Content {
    let rootMessageId: String
    let subject: String?
    let author: String?
    let startedAt: Date?
    let lastActivityAt: Date
    let messageCount: Int64
    let missingMessageCount: Int64
    let kind: ThreadKind
    let mailingLists: [MailingListView]
    let subsystems: [SubsystemView]
    let patchSeries: [PatchSeriesView]

    init(_ value: ThreadSummary) {
        rootMessageId = value.rootMessageID
        subject = value.subject
        author = value.author
        startedAt = value.startedAt
        lastActivityAt = value.lastActivityAt
        messageCount = value.messageCount
        missingMessageCount =
            value.missingMessageCount
        kind = value.kind
        mailingLists = value.mailingLists.map(
            MailingListView.init
        )
        subsystems = value.subsystems.map(
            SubsystemView.init
        )
        patchSeries = value.patchSeries.map(
            PatchSeriesView.init
        )
    }
}

struct PatchPositionView: Content {
    let partIndex: Int32
    let totalParts: Int32
}

struct ThreadMessagesView: Content {
    let rootMessageId: String
    let items: [MessageDetailView]
    let pagination: PaginationView

    init(_ value: ThreadMessagePageResult) {
        rootMessageId = value.rootMessageID
        items = value.items.map(
            { MessageDetailView($0.detail) }
        )
        pagination = PaginationView(
            previousCursor:
                value.previousCursor,
            nextCursor:
                value.nextCursor
        )
    }
}

struct MailboxView: Content {
    let name: String?
    let email: String

    init(_ value: MailboxSummary) {
        name = value.name
        email = value.email
    }
}

struct MessageDetailView: Content {
    let messageId: String
    let rootMessageId: String
    let inReplyToMessageId: String?
    let referenceMessageIds: [String]
    let availability: String
    let subject: String?
    let author: String?
    let to: [MailboxView]
    let cc: [MailboxView]
    let sentAt: Date?
    let body: String?
    let patch: PatchPositionView?
    let mailingLists: [MailingListView]
    let subsystems: [SubsystemView]
    let loreUrl: String

    init(_ value: MessageDetail) {
        messageId = value.messageID
        rootMessageId = value.rootMessageID
        inReplyToMessageId =
            value.inReplyToMessageID
        referenceMessageIds =
            value.referenceMessageIDs
        availability = value.availability.rawValue
        subject = value.subject
        author = value.author
        to = value.to.map(MailboxView.init)
        cc = value.cc.map(MailboxView.init)
        sentAt = value.sentAt
        body = value.body

        if let partIndex = value.patchPartIndex,
           let totalParts = value.patchTotalParts
        {
            patch = PatchPositionView(
                partIndex: partIndex,
                totalParts: totalParts
            )
        } else {
            patch = nil
        }

        mailingLists = value.mailingLists.map(
            MailingListView.init
        )
        subsystems = value.subsystems.map(
            SubsystemView.init
        )
        loreUrl =
            "https://lore.kernel.org/r/"
            + value.messageID.addingPercentEncoding(
                withAllowedCharacters:
                    .urlPathComponentAllowed
            )!
    }
}

struct MailingListCollectionView: Content {
    let items: [MailingListView]
}

struct SubsystemCollectionView: Content {
    let items: [SubsystemView]
}

private extension CharacterSet {
    static var urlPathComponentAllowed: CharacterSet {
        var value = CharacterSet.urlPathAllowed
        value.remove(charactersIn: "/?#%")
        return value
    }
}
