import Foundation
import PostgresNIO
import Vapor

struct PostgresReadRepository: Sendable {
    let client: PostgresClient

    func threads(
        scope: ThreadPageScope,
        cursor: ThreadCursor?,
        logger: Logger
    ) async throws -> ThreadPageResult {
        let fetchLimit = scope.limit + 1
        let rows: PostgresRowSequence

        switch cursor?.direction {
        case .previous:
            let cursor = cursor!
            rows = try await client.query(
                """
                WITH page AS MATERIALIZED (
                    SELECT t.*
                    FROM threads AS t
                    WHERE (
                        t.last_updated_at,
                        t.root_message_id
                    ) > (
                        \(cursor.anchorUpdatedAt),
                        \(cursor.anchorRootMessageID)
                    )
                      AND (
                        \(scope.mailingList == nil)
                        OR EXISTS (
                            SELECT 1
                            FROM messages AS filter_message
                            JOIN messages_mailing_lists AS filter_link
                              ON filter_link.message_id = filter_message.id
                            JOIN mailing_lists AS filter_list
                              ON filter_list.id = filter_link.mailing_list_id
                            WHERE filter_message.thread_id = t.id
                              AND filter_list.archive_group = \(scope.mailingList)
                        )
                      )
                      AND (
                        \(scope.subsystem == nil)
                        OR EXISTS (
                            SELECT 1
                            FROM threads_subsystems AS filter_link
                            JOIN subsystems AS filter_subsystem
                              ON filter_subsystem.id = filter_link.subsystem_id
                            WHERE filter_link.thread_id = t.id
                              AND filter_subsystem.name = \(scope.subsystem)
                        )
                      )
                      AND (
                        \(scope.kind == nil)
                        OR (
                            \(scope.kind == .patchSeries)
                            AND EXISTS (
                                SELECT 1
                                FROM patchsets AS filter_patchset
                                WHERE filter_patchset.thread_id = t.id
                            )
                        )
                        OR (
                            \(scope.kind == .discussion)
                            AND NOT EXISTS (
                                SELECT 1
                                FROM patchsets AS filter_patchset
                                WHERE filter_patchset.thread_id = t.id
                            )
                        )
                      )
                    ORDER BY
                        t.last_updated_at ASC,
                        t.root_message_id ASC
                    LIMIT \(fetchLimit)
                )
                \(unescaped: threadProjectionSQL)
                ORDER BY
                    t.last_updated_at ASC,
                    t.root_message_id ASC
                """,
                logger: logger
            )

        case .next:
            let cursor = cursor!
            rows = try await client.query(
                """
                WITH page AS MATERIALIZED (
                    SELECT t.*
                    FROM threads AS t
                    WHERE (
                        t.last_updated_at,
                        t.root_message_id
                    ) < (
                        \(cursor.anchorUpdatedAt),
                        \(cursor.anchorRootMessageID)
                    )
                      AND (
                        \(scope.mailingList == nil)
                        OR EXISTS (
                            SELECT 1
                            FROM messages AS filter_message
                            JOIN messages_mailing_lists AS filter_link
                              ON filter_link.message_id = filter_message.id
                            JOIN mailing_lists AS filter_list
                              ON filter_list.id = filter_link.mailing_list_id
                            WHERE filter_message.thread_id = t.id
                              AND filter_list.archive_group = \(scope.mailingList)
                        )
                      )
                      AND (
                        \(scope.subsystem == nil)
                        OR EXISTS (
                            SELECT 1
                            FROM threads_subsystems AS filter_link
                            JOIN subsystems AS filter_subsystem
                              ON filter_subsystem.id = filter_link.subsystem_id
                            WHERE filter_link.thread_id = t.id
                              AND filter_subsystem.name = \(scope.subsystem)
                        )
                      )
                      AND (
                        \(scope.kind == nil)
                        OR (
                            \(scope.kind == .patchSeries)
                            AND EXISTS (
                                SELECT 1
                                FROM patchsets AS filter_patchset
                                WHERE filter_patchset.thread_id = t.id
                            )
                        )
                        OR (
                            \(scope.kind == .discussion)
                            AND NOT EXISTS (
                                SELECT 1
                                FROM patchsets AS filter_patchset
                                WHERE filter_patchset.thread_id = t.id
                            )
                        )
                      )
                    ORDER BY
                        t.last_updated_at DESC,
                        t.root_message_id DESC
                    LIMIT \(fetchLimit)
                )
                \(unescaped: threadProjectionSQL)
                ORDER BY
                    t.last_updated_at DESC,
                    t.root_message_id DESC
                """,
                logger: logger
            )

        case nil:
            rows = try await client.query(
                """
                WITH page AS MATERIALIZED (
                    SELECT t.*
                    FROM threads AS t
                    WHERE (
                        \(scope.mailingList == nil)
                        OR EXISTS (
                            SELECT 1
                            FROM messages AS filter_message
                            JOIN messages_mailing_lists AS filter_link
                              ON filter_link.message_id = filter_message.id
                            JOIN mailing_lists AS filter_list
                              ON filter_list.id = filter_link.mailing_list_id
                            WHERE filter_message.thread_id = t.id
                              AND filter_list.archive_group = \(scope.mailingList)
                        )
                      )
                      AND (
                        \(scope.subsystem == nil)
                        OR EXISTS (
                            SELECT 1
                            FROM threads_subsystems AS filter_link
                            JOIN subsystems AS filter_subsystem
                              ON filter_subsystem.id = filter_link.subsystem_id
                            WHERE filter_link.thread_id = t.id
                              AND filter_subsystem.name = \(scope.subsystem)
                        )
                      )
                      AND (
                        \(scope.kind == nil)
                        OR (
                            \(scope.kind == .patchSeries)
                            AND EXISTS (
                                SELECT 1
                                FROM patchsets AS filter_patchset
                                WHERE filter_patchset.thread_id = t.id
                            )
                        )
                        OR (
                            \(scope.kind == .discussion)
                            AND NOT EXISTS (
                                SELECT 1
                                FROM patchsets AS filter_patchset
                                WHERE filter_patchset.thread_id = t.id
                            )
                        )
                      )
                    ORDER BY
                        t.last_updated_at DESC,
                        t.root_message_id DESC
                    LIMIT \(fetchLimit)
                )
                \(unescaped: threadProjectionSQL)
                ORDER BY
                    t.last_updated_at DESC,
                    t.root_message_id DESC
                """,
                logger: logger
            )
        }

        var items = try await decodeThreads(rows)
        let hasExtra = items.count > scope.limit

        if hasExtra {
            items.removeLast()
        }

        if cursor?.direction == .previous {
            items.reverse()
        }

        let hasPrevious: Bool
        let hasNext: Bool

        switch cursor?.direction {
        case .previous:
            hasPrevious = hasExtra
            hasNext = !items.isEmpty
        case .next:
            hasPrevious = !items.isEmpty
            hasNext = hasExtra
        case nil:
            hasPrevious = false
            hasNext = hasExtra
        }

        return ThreadPageResult(
            items: items,
            previousCursor: try hasPrevious
                ? items.first.map {
                    try makeThreadCursor(
                        direction: .previous,
                        anchor: $0,
                        scope: scope
                    )
                }
                : nil,
            nextCursor: try hasNext
                ? items.last.map {
                    try makeThreadCursor(
                        direction: .next,
                        anchor: $0,
                        scope: scope
                    )
                }
                : nil
        )
    }

    func thread(
        rootMessageID: MessageIdentifier,
        logger: Logger
    ) async throws -> ThreadSummary? {
        let rows = try await client.query(
            """
            WITH page AS MATERIALIZED (
                SELECT t.*
                FROM threads AS t
                WHERE t.root_message_id = \(rootMessageID.value)
            )
            \(unescaped: threadProjectionSQL)
            """,
            logger: logger
        )

        return try await decodeThreads(rows).first
    }

    func messages(
        rootMessageID: MessageIdentifier,
        limit: Int,
        cursor: MessageCursor?,
        logger: Logger
    ) async throws -> ThreadMessagePageResult? {
        guard let threadID = try await threadDatabaseID(
            rootMessageID: rootMessageID,
            logger: logger
        ) else {
            return nil
        }

        let fetchLimit = limit + 1
        let rows: PostgresRowSequence

        switch cursor?.direction {
        case .previous:
            let cursor = cursor!
            rows = try await client.query(
                """
                \(unescaped: messageProjectionSQL)
                WHERE message.thread_id = \(threadID)
                  AND (
                    COALESCE(
                        message.sent_at,
                        message.created_at
                    ),
                    message.message_id
                  ) < (
                    \(cursor.anchorSortAt),
                    \(cursor.anchorMessageID)
                  )
                ORDER BY
                    COALESCE(
                        message.sent_at,
                        message.created_at
                    ) DESC,
                    message.message_id DESC
                LIMIT \(fetchLimit)
                """,
                logger: logger
            )

        case .next:
            let cursor = cursor!
            rows = try await client.query(
                """
                \(unescaped: messageProjectionSQL)
                WHERE message.thread_id = \(threadID)
                  AND (
                    COALESCE(
                        message.sent_at,
                        message.created_at
                    ),
                    message.message_id
                  ) > (
                    \(cursor.anchorSortAt),
                    \(cursor.anchorMessageID)
                  )
                ORDER BY
                    COALESCE(
                        message.sent_at,
                        message.created_at
                    ) ASC,
                    message.message_id ASC
                LIMIT \(fetchLimit)
                """,
                logger: logger
            )

        case nil:
            rows = try await client.query(
                """
                \(unescaped: messageProjectionSQL)
                WHERE message.thread_id = \(threadID)
                ORDER BY
                    COALESCE(
                        message.sent_at,
                        message.created_at
                    ) ASC,
                    message.message_id ASC
                LIMIT \(fetchLimit)
                """,
                logger: logger
            )
        }

        var items = try await decodeThreadMessages(rows)
        let hasExtra = items.count > limit

        if hasExtra {
            items.removeLast()
        }

        if cursor?.direction == .previous {
            items.reverse()
        }

        let hasPrevious: Bool
        let hasNext: Bool

        switch cursor?.direction {
        case .previous:
            hasPrevious = hasExtra
            hasNext = !items.isEmpty
        case .next:
            hasPrevious = !items.isEmpty
            hasNext = hasExtra
        case nil:
            hasPrevious = false
            hasNext = hasExtra
        }

        return ThreadMessagePageResult(
            rootMessageID: rootMessageID.value,
            items: items,
            previousCursor: try hasPrevious
                ? items.first.map {
                    try makeMessageCursor(
                        direction: .previous,
                        anchor: $0,
                        rootMessageID:
                            rootMessageID.value,
                        limit: limit
                    )
                }
                : nil,
            nextCursor: try hasNext
                ? items.last.map {
                    try makeMessageCursor(
                        direction: .next,
                        anchor: $0,
                        rootMessageID:
                            rootMessageID.value,
                        limit: limit
                    )
                }
                : nil
        )
    }

    func message(
        messageID: MessageIdentifier,
        logger: Logger
    ) async throws -> MessageDetail? {
        let rows = try await client.query(
            """
            SELECT
                message.message_id,
                thread.root_message_id,
                message.in_reply_to,
                message.references_ids,
                message.is_placeholder,
                message.subject,
                message.author,
                message.sent_at,
                message.body,
                patch_data.part_index,
                patch_data.total_parts,
                recipient_data.to_names,
                recipient_data.to_emails,
                recipient_data.cc_names,
                recipient_data.cc_emails,
                mailing_data.names,
                mailing_data.archive_groups,
                subsystem_data.names,
                subsystem_data.addresses
            FROM messages AS message
            JOIN threads AS thread
              ON thread.id = message.thread_id
            LEFT JOIN LATERAL (
                SELECT
                    COALESCE(patch.part_index, 0) AS part_index,
                    patchset.total_parts
                FROM patchsets AS patchset
                LEFT JOIN patches AS patch
                  ON patch.patchset_id = patchset.id
                 AND patch.message_id = message.message_id
                WHERE patchset.cover_letter_message_id = message.message_id
                   OR patch.message_id IS NOT NULL
                ORDER BY patchset.id
                LIMIT 1
            ) AS patch_data ON true
            LEFT JOIN LATERAL (
                SELECT
                    COALESCE(
                        array_agg(
                            COALESCE(person.name, '')
                            ORDER BY person.email
                        )
                            FILTER (WHERE recipient.recipient_type = 'To'),
                        ARRAY[]::text[]
                    ) AS to_names,
                    COALESCE(
                        array_agg(person.email ORDER BY person.email)
                            FILTER (WHERE recipient.recipient_type = 'To'),
                        ARRAY[]::text[]
                    ) AS to_emails,
                    COALESCE(
                        array_agg(
                            COALESCE(person.name, '')
                            ORDER BY person.email
                        )
                            FILTER (WHERE recipient.recipient_type = 'Cc'),
                        ARRAY[]::text[]
                    ) AS cc_names,
                    COALESCE(
                        array_agg(person.email ORDER BY person.email)
                            FILTER (WHERE recipient.recipient_type = 'Cc'),
                        ARRAY[]::text[]
                    ) AS cc_emails
                FROM messages_recipients AS recipient
                JOIN people AS person
                  ON person.id = recipient.person_id
                WHERE recipient.message_id = message.id
            ) AS recipient_data ON true
            LEFT JOIN LATERAL (
                SELECT
                    COALESCE(
                        array_agg(data.name ORDER BY data.archive_group),
                        ARRAY[]::text[]
                    ) AS names,
                    COALESCE(
                        array_agg(data.archive_group ORDER BY data.archive_group),
                        ARRAY[]::text[]
                    ) AS archive_groups
                FROM (
                    SELECT DISTINCT
                        mailing_list.name,
                        mailing_list.archive_group
                    FROM messages_mailing_lists AS link
                    JOIN mailing_lists AS mailing_list
                      ON mailing_list.id = link.mailing_list_id
                    WHERE link.message_id = message.id
                ) AS data
            ) AS mailing_data ON true
            LEFT JOIN LATERAL (
                SELECT
                    COALESCE(
                        array_agg(subsystem.name ORDER BY subsystem.name),
                        ARRAY[]::text[]
                    ) AS names,
                    COALESCE(
                        array_agg(
                            COALESCE(subsystem.mailing_list_address, '')
                            ORDER BY subsystem.name
                        ),
                        ARRAY[]::text[]
                    ) AS addresses
                FROM messages_subsystems AS link
                JOIN subsystems AS subsystem
                  ON subsystem.id = link.subsystem_id
                WHERE link.message_id = message.id
            ) AS subsystem_data ON true
            WHERE message.message_id = \(messageID.value)
            """,
            logger: logger
        )

        for try await row in rows {
            let cells = Array(row)
            let storedMessageID = try cells[0]
                .decode(String.self)
            let rootMessageID = try cells[1]
                .decode(String.self)
            let inReplyTo = try cells[2]
                .decode(String?.self)
            let references = try cells[3]
                .decode([String].self)
            let isPlaceholder = try cells[4]
                .decode(Bool.self)
            let subject = try cells[5]
                .decode(String?.self)
            let author = try cells[6]
                .decode(String?.self)
            let sentAt = try cells[7]
                .decode(Date?.self)
            let body = try cells[8]
                .decode(String.self)
            let partIndex = try cells[9]
                .decode(Int32?.self)
            let totalParts = try cells[10]
                .decode(Int32?.self)
            let toNames = try cells[11]
                .decode([String].self)
            let toEmails = try cells[12]
                .decode([String].self)
            let ccNames = try cells[13]
                .decode([String].self)
            let ccEmails = try cells[14]
                .decode([String].self)
            let mailingNames = try cells[15]
                .decode([String].self)
            let mailingGroups = try cells[16]
                .decode([String].self)
            let subsystemNames = try cells[17]
                .decode([String].self)
            let subsystemAddresses = try cells[18]
                .decode([String].self)
            let available = !isPlaceholder

            return MessageDetail(
                messageID: storedMessageID,
                rootMessageID: rootMessageID,
                inReplyToMessageID: inReplyTo,
                referenceMessageIDs: references,
                availability:
                    available ? .available : .missing,
                subject: available ? subject : nil,
                author: available ? author : nil,
                to: zipMailboxes(
                    names: toNames,
                    emails: toEmails
                ),
                cc: zipMailboxes(
                    names: ccNames,
                    emails: ccEmails
                ),
                sentAt: available ? sentAt : nil,
                body: available ? body : nil,
                patchPartIndex:
                    available ? partIndex : nil,
                patchTotalParts:
                    available ? totalParts : nil,
                mailingLists: zipMailingLists(
                    names: mailingNames,
                    archiveGroups: mailingGroups
                ),
                subsystems: zipSubsystems(
                    names: subsystemNames,
                    addresses: subsystemAddresses
                )
            )
        }

        return nil
    }

    func mailingLists(
        logger: Logger
    ) async throws -> [MailingListSummary] {
        let rows = try await client.query(
            """
            SELECT
                name,
                archive_group
            FROM mailing_lists
            ORDER BY name, archive_group
            """,
            logger: logger
        )

        var values: [MailingListSummary] = []

        for try await row in rows {
            let value = try row.decode(
                (String, String).self
            )

            values.append(
                MailingListSummary(
                    name: value.0,
                    archiveGroup: value.1
                )
            )
        }

        return values
    }

    func subsystems(
        logger: Logger
    ) async throws -> [SubsystemSummary] {
        let rows = try await client.query(
            """
            SELECT
                name,
                mailing_list_address
            FROM subsystems
            ORDER BY name
            """,
            logger: logger
        )

        var values: [SubsystemSummary] = []

        for try await row in rows {
            let value = try row.decode(
                (String, String?).self
            )

            values.append(
                SubsystemSummary(
                    name: value.0,
                    mailingListAddress: value.1
                )
            )
        }

        return values
    }

    private func threadDatabaseID(
        rootMessageID: MessageIdentifier,
        logger: Logger
    ) async throws -> Int64? {
        let rows = try await client.query(
            """
            SELECT id
            FROM threads
            WHERE root_message_id = \(rootMessageID.value)
            """,
            logger: logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        return nil
    }

    private func decodeThreads(
        _ rows: PostgresRowSequence
    ) async throws -> [ThreadSummary] {
        var values: [ThreadSummary] = []

        for try await row in rows {
            let cells = Array(row)
            let rootMessageID = try cells[0]
                .decode(String.self)
            let subject = try cells[1]
                .decode(String?.self)
            let author = try cells[2]
                .decode(String?.self)
            let startedAt = try cells[3]
                .decode(Date?.self)
            let lastActivityAt = try cells[4]
                .decode(Date.self)
            let messageCount = try cells[5]
                .decode(Int64.self)
            let missingMessageCount = try cells[6]
                .decode(Int64.self)
            let mailingNames = try cells[7]
                .decode([String].self)
            let mailingGroups = try cells[8]
                .decode([String].self)
            let subsystemNames = try cells[9]
                .decode([String].self)
            let subsystemAddresses = try cells[10]
                .decode([String].self)
            let coverMessageIDs = try cells[11]
                .decode([String].self)
            let statuses = try cells[12]
                .decode([String].self)
            let totalParts = try cells[13]
                .decode([Int32].self)
            let receivedParts = try cells[14]
                .decode([Int32].self)

            values.append(
                ThreadSummary(
                    rootMessageID: rootMessageID,
                    subject: subject,
                    author: author,
                    startedAt: startedAt,
                    lastActivityAt: lastActivityAt,
                    messageCount: messageCount,
                    missingMessageCount:
                        missingMessageCount,
                    mailingLists: zipMailingLists(
                        names: mailingNames,
                        archiveGroups: mailingGroups
                    ),
                    subsystems: zipSubsystems(
                        names: subsystemNames,
                        addresses: subsystemAddresses
                    ),
                    patchSeries: zipPatchSeries(
                        coverMessageIDs:
                            coverMessageIDs,
                        statuses: statuses,
                        totalParts: totalParts,
                        receivedParts: receivedParts
                    )
                )
            )
        }

        return values
    }

    private func decodeThreadMessages(
        _ rows: PostgresRowSequence
    ) async throws -> [ThreadMessageSummary] {
        var values: [ThreadMessageSummary] = []

        for try await row in rows {
            let value = try row.decode(
                (
                    String,
                    String?,
                    [String],
                    Bool,
                    String?,
                    String?,
                    Date?,
                    String,
                    Int32?,
                    Int32?,
                    Date
                ).self
            )

            let available = !value.3

            values.append(
                ThreadMessageSummary(
                    messageID: value.0,
                    inReplyToMessageID: value.1,
                    referenceMessageIDs: value.2,
                    availability:
                        available ? .available : .missing,
                    subject: available ? value.4 : nil,
                    author: available ? value.5 : nil,
                    sentAt: available ? value.6 : nil,
                    bodyPreview:
                        available ? value.7 : nil,
                    patchPartIndex:
                        available ? value.8 : nil,
                    patchTotalParts:
                        available ? value.9 : nil,
                    sortAt: value.10
                )
            )
        }

        return values
    }

    private func makeThreadCursor(
        direction: PageDirection,
        anchor: ThreadSummary,
        scope: ThreadPageScope
    ) throws -> String {
        try PaginationCursorCodec.encode(
            ThreadCursor(
                version: 1,
                direction: direction,
                anchorUpdatedAtMicroseconds:
                    anchor.lastActivityAt
                        .postgresMicrosecondsSince1970,
                anchorRootMessageID:
                    anchor.rootMessageID,
                scope: scope
            )
        )
    }

    private func makeMessageCursor(
        direction: PageDirection,
        anchor: ThreadMessageSummary,
        rootMessageID: String,
        limit: Int
    ) throws -> String {
        try PaginationCursorCodec.encode(
            MessageCursor(
                version: 1,
                direction: direction,
                rootMessageID: rootMessageID,
                anchorSortAtMicroseconds:
                    anchor.sortAt
                        .postgresMicrosecondsSince1970,
                anchorMessageID: anchor.messageID,
                limit: limit
            )
        )
    }

    private func zipMailingLists(
        names: [String],
        archiveGroups: [String]
    ) -> [MailingListSummary] {
        zip(names, archiveGroups).map {
            MailingListSummary(
                name: $0,
                archiveGroup: $1
            )
        }
    }

    private func zipSubsystems(
        names: [String],
        addresses: [String]
    ) -> [SubsystemSummary] {
        zip(names, addresses).map {
            SubsystemSummary(
                name: $0,
                mailingListAddress:
                    $1.isEmpty ? nil : $1
            )
        }
    }

    private func zipPatchSeries(
        coverMessageIDs: [String],
        statuses: [String],
        totalParts: [Int32],
        receivedParts: [Int32]
    ) -> [PatchSeriesSummary] {
        let count = [
            coverMessageIDs.count,
            statuses.count,
            totalParts.count,
            receivedParts.count,
        ].min() ?? 0

        return (0..<count).map {
            PatchSeriesSummary(
                coverLetterMessageID:
                    coverMessageIDs[$0].isEmpty
                    ? nil
                    : coverMessageIDs[$0],
                status: statuses[$0],
                totalParts: totalParts[$0],
                receivedParts: receivedParts[$0]
            )
        }
    }

    private func zipMailboxes(
        names: [String],
        emails: [String]
    ) -> [MailboxSummary] {
        zip(names, emails).map {
            MailboxSummary(
                name: $0.isEmpty ? nil : $0,
                email: $1
            )
        }
    }

    private var threadProjectionSQL: String {
        """
        SELECT
            t.root_message_id,
            t.subject,
            CASE
                WHEN root.is_placeholder THEN NULL
                ELSE root.author
            END,
            CASE
                WHEN root.is_placeholder THEN NULL
                ELSE root.sent_at
            END,
            t.last_updated_at,
            count_data.message_count,
            count_data.missing_message_count,
            mailing_data.names,
            mailing_data.archive_groups,
            subsystem_data.names,
            subsystem_data.addresses,
            patch_data.cover_message_ids,
            patch_data.statuses,
            patch_data.total_parts,
            patch_data.received_parts
        FROM page AS t
        LEFT JOIN messages AS root
          ON root.message_id = t.root_message_id
        LEFT JOIN LATERAL (
            SELECT
                COUNT(*) FILTER (
                    WHERE NOT message.is_placeholder
                )::bigint AS message_count,
                COUNT(*) FILTER (
                    WHERE message.is_placeholder
                )::bigint AS missing_message_count
            FROM messages AS message
            WHERE message.thread_id = t.id
        ) AS count_data ON true
        LEFT JOIN LATERAL (
            SELECT
                COALESCE(
                    array_agg(data.name ORDER BY data.archive_group),
                    ARRAY[]::text[]
                ) AS names,
                COALESCE(
                    array_agg(data.archive_group ORDER BY data.archive_group),
                    ARRAY[]::text[]
                ) AS archive_groups
            FROM (
                SELECT DISTINCT
                    mailing_list.name,
                    mailing_list.archive_group
                FROM messages AS message
                JOIN messages_mailing_lists AS link
                  ON link.message_id = message.id
                JOIN mailing_lists AS mailing_list
                  ON mailing_list.id = link.mailing_list_id
                WHERE message.thread_id = t.id
            ) AS data
        ) AS mailing_data ON true
        LEFT JOIN LATERAL (
            SELECT
                COALESCE(
                    array_agg(subsystem.name ORDER BY subsystem.name),
                    ARRAY[]::text[]
                ) AS names,
                COALESCE(
                    array_agg(
                        COALESCE(subsystem.mailing_list_address, '')
                        ORDER BY subsystem.name
                    ),
                    ARRAY[]::text[]
                ) AS addresses
            FROM threads_subsystems AS link
            JOIN subsystems AS subsystem
              ON subsystem.id = link.subsystem_id
            WHERE link.thread_id = t.id
        ) AS subsystem_data ON true
        LEFT JOIN LATERAL (
            SELECT
                COALESCE(
                    array_agg(
                        COALESCE(patchset.cover_letter_message_id, '')
                        ORDER BY patchset.id
                    ),
                    ARRAY[]::text[]
                ) AS cover_message_ids,
                COALESCE(
                    array_agg(patchset.status ORDER BY patchset.id),
                    ARRAY[]::text[]
                ) AS statuses,
                COALESCE(
                    array_agg(patchset.total_parts ORDER BY patchset.id),
                    ARRAY[]::integer[]
                ) AS total_parts,
                COALESCE(
                    array_agg(patchset.received_parts ORDER BY patchset.id),
                    ARRAY[]::integer[]
                ) AS received_parts
            FROM patchsets AS patchset
            WHERE patchset.thread_id = t.id
        ) AS patch_data ON true
        """
    }

    private var messageProjectionSQL: String {
        """
        SELECT
            message.message_id,
            message.in_reply_to,
            message.references_ids,
            message.is_placeholder,
            message.subject,
            message.author,
            message.sent_at,
            LEFT(message.body, 280),
            patch_data.part_index,
            patch_data.total_parts,
            COALESCE(
                message.sent_at,
                message.created_at
            ) AS sort_at
        FROM messages AS message
        LEFT JOIN LATERAL (
            SELECT
                COALESCE(patch.part_index, 0) AS part_index,
                patchset.total_parts
            FROM patchsets AS patchset
            LEFT JOIN patches AS patch
              ON patch.patchset_id = patchset.id
             AND patch.message_id = message.message_id
            WHERE patchset.cover_letter_message_id = message.message_id
               OR patch.message_id IS NOT NULL
            ORDER BY patchset.id
            LIMIT 1
        ) AS patch_data ON true
        """
    }
}
