import Vapor

struct MailSearchResultView: Content {
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
    let score: Double
    let snippet: String

    init(_ value: MailSearchResult) {
        let thread = value.thread
        rootMessageId = thread.rootMessageID
        subject = thread.subject
        author = thread.author
        startedAt = thread.startedAt
        lastActivityAt = thread.lastActivityAt
        messageCount = thread.messageCount
        missingMessageCount =
            thread.missingMessageCount
        kind = thread.kind
        mailingLists = thread.mailingLists.map(
            MailingListView.init
        )
        subsystems = thread.subsystems.map(
            SubsystemView.init
        )
        patchSeries = thread.patchSeries.map(
            PatchSeriesView.init
        )
        score = value.score
        snippet = value.snippet
    }
}

struct MailSearchCollectionView: Content {
    let items: [MailSearchResultView]
    let pagination: PaginationView

    init(_ value: MailSearchPageResult) {
        items = value.items.map(
            MailSearchResultView.init
        )
        pagination = PaginationView(
            previousCursor: value.previousCursor,
            nextCursor: value.nextCursor
        )
    }
}
