//
//  PostgresIngestService.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation
import PostgresNIO
import Vapor

enum PostgresIngestError:
    Error,
    Sendable,
    Equatable
{
    case missingEpoch(
        mailingListID: Int64,
        epoch: Int32
    )

    case cursorMismatch(
        expected: String?,
        actual: String?
    )

    case missingThread(String)
    case missingMessage(String)
}

struct PostgresIngestResult:
    Sendable,
    Equatable
{
    let messageID: Int64
    let threadID: Int64
    let wasAlreadyIngested: Bool
}

struct PreparedPublicInboxMessage:
    Sendable
{
    let commitOID: String
    let blobOID: String
    let parsed: ParsedIngestMessage
}

struct PostgresIngestService: Sendable {

    private struct NormalizedPublicInboxMessage:
        Sendable
    {
        let blobOID: String
        let parsed: ParsedIngestMessage
    }

    private struct MessageState: Sendable {
        let id: Int64
        var threadID: Int64
    }

    private struct ThreadMetadataInput:
        Sendable
    {
        var threadID: Int64
        let rootCandidateMessageID: String
        let subject: String
        let timestamp: Date
    }

    private struct BatchPersistenceState:
        Sendable
    {
        var messagesByMessageID: [String: MessageState] = [:]

        var mailingListBlobOIDByMessageDatabaseID:
            [Int64: String] = [:]

        var threadMetadataInputs:
            [ThreadMetadataInput] = []

        var recipientsByMessageDatabaseID: [Int64: [ResolvedBatchRecipient]] = [:]

        mutating func remapThread(
            from sourceThreadID: Int64,
            to targetThreadID: Int64
        ) {
            for messageID in Array(
                messagesByMessageID.keys
            ) {
                guard
                    var state =
                        messagesByMessageID[
                            messageID
                        ],
                    state.threadID
                        == sourceThreadID
                else {
                    continue
                }

                state.threadID =
                    targetThreadID

                messagesByMessageID[
                    messageID
                ] = state
            }

            for index
                in threadMetadataInputs.indices
            {
                guard
                    threadMetadataInputs[
                        index
                    ].threadID == sourceThreadID
                else {
                    continue
                }

                threadMetadataInputs[
                    index
                ].threadID = targetThreadID
            }
        }
    }

    let client: PostgresClient

    func archiveCursor(
        mailingListID: Int64,
        epoch: Int32,
        logger: Logger
    ) async throws -> String? {
        try await client.withTransaction(
            logger: logger
        ) { connection in
            try await ensureEpoch(
                mailingListID: mailingListID,
                epoch: epoch,
                connection: connection,
                logger: logger
            )

            return try await lockedCursor(
                mailingListID: mailingListID,
                epoch: epoch,
                connection: connection,
                logger: logger
            )
        }
    }

    func ingestBatch(
        _ messages:
            [PreparedPublicInboxMessage],
        mailingListID: Int64,
        epoch: Int32,
        expectedPreviousCommitOID: String?,
        logger: Logger
    ) async throws -> [PostgresIngestResult] {
        guard let finalMessage = messages.last
        else {
            return []
        }

        let normalized = messages.map {
            NormalizedPublicInboxMessage(
                blobOID: $0.blobOID,
                parsed:
                    PostgresTextNormalizer
                    .normalize($0.parsed)
            )
        }

        return try await client.withTransaction(
            logger: logger
        ) { connection in
            try await ensureEpoch(
                mailingListID: mailingListID,
                epoch: epoch,
                connection: connection,
                logger: logger
            )

            let currentCursor =
                try await lockedCursor(
                    mailingListID:
                        mailingListID,
                    epoch: epoch,
                    connection: connection,
                    logger: logger
                )

            guard
                currentCursor
                    == expectedPreviousCommitOID
            else {
                throw
                    PostgresIngestError
                    .cursorMismatch(
                        expected:
                            expectedPreviousCommitOID,
                        actual: currentCursor
                    )
            }

            let recipientService =
                PostgresRecipientBatchService()

            let resolvedRecipients =
                try await recipientService
                .resolvePeople(
                    messages:
                        normalized.map(\.parsed),
                    connection: connection,
                    logger: logger
                )

            var batchState =
                BatchPersistenceState()

            var results: [PostgresIngestResult] = []
            results.reserveCapacity(
                normalized.count
            )

            for (
                messageIndex,
                message
            ) in normalized.enumerated() {
                let persisted =
                    try await persistMessage(
                        blobOID:
                            message.blobOID,
                        parsed:
                            message.parsed,
                        batchState:
                            &batchState,
                        connection: connection,
                        logger: logger
                    )

                batchState
                    .recipientsByMessageDatabaseID[
                        persisted.id
                    ] =
                    resolvedRecipients
                    .recipients(
                        forMessageAt:
                            messageIndex
                    )

                results.append(
                    PostgresIngestResult(
                        messageID: persisted.id,
                        threadID:
                            persisted.threadID,
                        wasAlreadyIngested:
                            false
                    )
                )
            }

            try await persistMailingListLinks(
                linksByMessageDatabaseID:
                    batchState
                    .mailingListBlobOIDByMessageDatabaseID,
                mailingListID: mailingListID,
                connection: connection,
                logger: logger
            )

            try await updateThreadMetadata(
                inputs:
                    batchState
                    .threadMetadataInputs,
                connection: connection,
                logger: logger
            )

            try await recipientService
                .replaceRecipients(
                    recipientsByMessageID:
                        batchState
                        .recipientsByMessageDatabaseID,
                    connection: connection,
                    logger: logger
                )

            try await advanceCursor(
                mailingListID: mailingListID,
                epoch: epoch,
                expectedPreviousCommitOID:
                    expectedPreviousCommitOID,
                commitOID:
                    finalMessage.commitOID,
                connection: connection,
                logger: logger
            )

            return results
        }
    }

    private func ensureEpoch(
        mailingListID: Int64,
        epoch: Int32,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            INSERT INTO mailing_list_archive_epochs (
                mailing_list_id,
                epoch
            )
            VALUES (
                \(mailingListID),
                \(epoch)
            )
            ON CONFLICT (
                mailing_list_id,
                epoch
            ) DO NOTHING
            """,
            on: connection,
            logger: logger
        )
    }

    private func persistMessage(
        blobOID: String,
        parsed: ParsedIngestMessage,
        batchState:
            inout BatchPersistenceState,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> (
        id: Int64,
        threadID: Int64
    ) {
        let message = parsed.message

        let threadAnchorMessageID =
            message.inReplyTo
            ?? message.messageID

        let timestamp =
            message.date
            ?? Date(timeIntervalSince1970: 0)

        let targetThreadID =
            try await ensureThread(
                for: threadAnchorMessageID,
                timestamp: timestamp,
                batchState: &batchState,
                connection: connection,
                logger: logger
            )

        let rows = try await connection.query(
            """
            INSERT INTO messages (
                message_id,
                thread_id,
                in_reply_to,
                references_ids,
                author,
                subject,
                sent_at,
                body,
                to_recipients,
                cc_recipients,
                is_placeholder,
                updated_at
            )
            VALUES (
                \(message.messageID),
                \(targetThreadID),
                \(message.inReplyTo),
                \(message.references),
                \(parsed.authorDisplayString),
                \(message.subject),
                \(message.date),
                \(message.textBody),
                \(parsed.toDisplayString),
                \(parsed.ccDisplayString),
                false,
                now()
            )
            ON CONFLICT (message_id) DO UPDATE
            SET
                thread_id =
                    EXCLUDED.thread_id,
                in_reply_to =
                    EXCLUDED.in_reply_to,
                references_ids =
                    EXCLUDED.references_ids,
                author =
                    EXCLUDED.author,
                subject =
                    EXCLUDED.subject,
                sent_at =
                    EXCLUDED.sent_at,
                body =
                    EXCLUDED.body,
                to_recipients =
                    EXCLUDED.to_recipients,
                cc_recipients =
                    EXCLUDED.cc_recipients,
                is_placeholder = false,
                updated_at = now()
            RETURNING
                new.id,
                old.thread_id
            """,
            logger: logger
        )

        guard
            let upserted =
                try await firstMessageUpsert(rows)
        else {
            throw
                PostgresIngestError
                .missingMessage(
                    message.messageID
                )
        }

        let messageDatabaseID = upserted.0
        let previousThreadID = upserted.1

        if let previousThreadID,
            previousThreadID != targetThreadID
        {
            try await mergeThread(
                previousThreadID,
                into: targetThreadID,
                connection: connection,
                logger: logger
            )

            batchState.remapThread(
                from: previousThreadID,
                to: targetThreadID
            )
        }

        batchState.messagesByMessageID[
            message.messageID
        ] = MessageState(
            id: messageDatabaseID,
            threadID: targetThreadID
        )

        try await PostgresPatchIngestService()
            .persist(
                parsed: parsed,
                threadID: targetThreadID,
                timestamp: timestamp,
                connection: connection,
                logger: logger
            )

        batchState
            .mailingListBlobOIDByMessageDatabaseID[
                messageDatabaseID
            ] = blobOID

        batchState.threadMetadataInputs.append(
            ThreadMetadataInput(
                threadID: targetThreadID,
                rootCandidateMessageID:
                    message.messageID,
                subject: message.subject,
                timestamp: timestamp
            )
        )

        return (
            messageDatabaseID,
            targetThreadID
        )
    }

    private func ensureThread(
        for messageID: String,
        timestamp: Date,
        batchState:
            inout BatchPersistenceState,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        if let cached =
            batchState
            .messagesByMessageID[
                messageID
            ]
        {
            return cached.threadID
        }

        if let existing =
            try await existingMessage(
                messageID: messageID,
                connection: connection,
                logger: logger
            )
        {
            batchState.messagesByMessageID[
                messageID
            ] = existing

            return existing.threadID
        }

        let threadRows = try await connection.query(
            """
            INSERT INTO threads (
                root_message_id,
                subject,
                last_updated_at
            )
            VALUES (
                \(messageID),
                NULL,
                \(timestamp)
            )
            ON CONFLICT (
                root_message_id
            ) DO UPDATE
            SET last_updated_at = GREATEST(
                threads.last_updated_at,
                EXCLUDED.last_updated_at
            )
            RETURNING id
            """,
            logger: logger
        )

        guard let threadID =
                try await firstInt64(threadRows)
        else {
            throw
                PostgresIngestError
                .missingThread(messageID)
        }

        let placeholderRows =
            try await connection.query(
                """
                INSERT INTO messages (
                    message_id,
                    thread_id,
                    subject,
                    sent_at,
                    is_placeholder
                )
                VALUES (
                    \(messageID),
                    \(threadID),
                    '(placeholder)',
                    \(timestamp),
                    true
                )
                ON CONFLICT (
                    message_id
                ) DO NOTHING
                RETURNING
                    id,
                    thread_id
                """,
                logger: logger
            )

        if let inserted =
            try await firstMessageState(
                placeholderRows
            )
        {
            batchState.messagesByMessageID[
                messageID
            ] = inserted

            return inserted.threadID
        }

        // Another transaction may have inserted
        // this Message-ID after the first lookup.
        guard
            let concurrentlyInserted =
                try await existingMessage(
                    messageID: messageID,
                    connection: connection,
                    logger: logger
                )
        else {
            throw
                PostgresIngestError
                .missingMessage(messageID)
        }

        batchState.messagesByMessageID[
            messageID
        ] = concurrentlyInserted

        return concurrentlyInserted.threadID
    }

    private func mergeThread(
         _ sourceThreadID: Int64,
         into targetThreadID: Int64,
         connection: PostgresConnection,
         logger: Logger
     ) async throws {
         try await execute(
             """
             UPDATE messages
             SET thread_id = \(targetThreadID)
             WHERE thread_id = \(sourceThreadID)
             """,
             on: connection,
             logger: logger
         )

         try await execute(
             """
             UPDATE patchsets
             SET
                 thread_id = \(targetThreadID),
                 updated_at = now()
             WHERE thread_id = \(sourceThreadID)
             """,
             on: connection,
             logger: logger
         )

         try await execute(
             """
             INSERT INTO threads_subsystems (
                 thread_id,
                 subsystem_id
             )
             SELECT
                 \(targetThreadID),
                 subsystem_id
             FROM threads_subsystems
             WHERE thread_id = \(sourceThreadID)
             ON CONFLICT DO NOTHING
             """,
             on: connection,
             logger: logger
         )

         try await execute(
             """
             DELETE FROM threads_subsystems
             WHERE thread_id = \(sourceThreadID)
             """,
             on: connection,
             logger: logger
         )

         try await execute(
             """
             DELETE FROM threads
             WHERE id = \(sourceThreadID)
             """,
             on: connection,
             logger: logger
         )
     }

    private func persistMailingListLinks(
        linksByMessageDatabaseID:
            [Int64: String],
        mailingListID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let links =
            linksByMessageDatabaseID
            .sorted {
                $0.key < $1.key
            }

        guard !links.isEmpty else {
            return
        }

        let messageIDs = links.map {
            $0.key
        }

        let blobOIDs = links.map {
            $0.value
        }

        try await execute(
            """
            INSERT INTO messages_mailing_lists (
                message_id,
                mailing_list_id,
                archive_blob_oid
            )
            SELECT
                input.message_id,
                \(mailingListID),
                input.archive_blob_oid
            FROM unnest(
                \(messageIDs)::bigint[],
                \(blobOIDs)::text[]
            ) AS input(
                message_id,
                archive_blob_oid
            )
            ON CONFLICT (
                message_id,
                mailing_list_id
            ) DO UPDATE
            SET archive_blob_oid =
                EXCLUDED.archive_blob_oid
            """,
            on: connection,
            logger: logger
        )
    }

    private func updateThreadMetadata(
        inputs: [ThreadMetadataInput],
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        guard !inputs.isEmpty else {
            return
        }

        let threadIDs = inputs.map {
            $0.threadID
        }

        let rootCandidateMessageIDs =
            inputs.map {
                $0.rootCandidateMessageID
            }

        let subjects = inputs.map {
            $0.subject
        }

        let timestamps = inputs.map {
            $0.timestamp
        }

        try await execute(
            """
            WITH metadata_input AS (
                SELECT
                    input.thread_id,
                    input.root_candidate_message_id,
                    input.subject,
                    input.message_timestamp,
                    input.ordinality
                FROM unnest(
                    \(threadIDs)::bigint[],
                    \(rootCandidateMessageIDs)::text[],
                    \(subjects)::text[],
                    \(timestamps)::timestamptz[]
                ) WITH ORDINALITY
                  AS input(
                      thread_id,
                      root_candidate_message_id,
                      subject,
                      message_timestamp,
                      ordinality
                  )
            ),
            metadata_by_thread AS (
                SELECT
                    thread.id AS thread_id,
                    COALESCE(
                        (
                            array_agg(
                                input.subject
                                ORDER BY
                                    input.ordinality
                                    DESC
                            )
                            FILTER (
                                WHERE
                                    input
                                    .root_candidate_message_id
                                    =
                                    thread
                                    .root_message_id
                            )
                        )[1],
                        thread.subject,
                        (
                            array_agg(
                                input.subject
                                ORDER BY
                                    input.ordinality
                            )
                        )[1]
                    ) AS subject,
                    GREATEST(
                        thread.last_updated_at,
                        max(
                            input.message_timestamp
                        )
                    ) AS last_updated_at
                FROM metadata_input AS input
                JOIN threads AS thread
                  ON thread.id =
                        input.thread_id
                GROUP BY thread.id
            )
            UPDATE threads AS thread
            SET
                subject = metadata.subject,
                last_updated_at =
                    metadata.last_updated_at
            FROM metadata_by_thread AS metadata
            WHERE thread.id =
                    metadata.thread_id
            """,
            on: connection,
            logger: logger
        )
    }

    private func existingMessage(
        messageID: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> MessageState? {
        let rows = try await connection.query(
            """
            SELECT
                id,
                thread_id
            FROM messages
            WHERE message_id = \(messageID)
            FOR UPDATE
            """,
            logger: logger
        )

        return try await firstMessageState(
            rows
        )
    }

    private func lockedCursor(
        mailingListID: Int64,
        epoch: Int32,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> String? {
        let rows = try await connection.query(
            """
            SELECT last_scanned_commit_oid
            FROM mailing_list_archive_epochs
            WHERE mailing_list_id = \(mailingListID)
              AND epoch = \(epoch)
            FOR UPDATE
            """,
            logger: logger
        )

        for try await row in rows {
            return try row.decode(
                String?.self
            )
        }

        throw PostgresIngestError.missingEpoch(
            mailingListID: mailingListID,
            epoch: epoch
        )
    }

    private func advanceCursor(
        mailingListID: Int64,
        epoch: Int32,
        expectedPreviousCommitOID: String?,
        commitOID: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let rows = try await connection.query(
            """
            UPDATE mailing_list_archive_epochs
            SET
                last_scanned_commit_oid =
                    \(commitOID),
                updated_at = now()
            WHERE mailing_list_id =
                    \(mailingListID)
              AND epoch = \(epoch)
              AND last_scanned_commit_oid
                    IS NOT DISTINCT FROM
                    \(expectedPreviousCommitOID)
            RETURNING last_scanned_commit_oid
            """,
            logger: logger
        )

        for try await _ in rows {
            return
        }

        throw PostgresIngestError.cursorMismatch(
            expected: expectedPreviousCommitOID,
            actual: try await lockedCursor(
                mailingListID: mailingListID,
                epoch: epoch,
                connection: connection,
                logger: logger
            )
        )
    }

    private func execute(
        _ query: PostgresQuery,
        on connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let rows = try await connection.query(
            query,
            logger: logger
        )

        for try await _ in rows {}
    }

    private func firstMessageState(
        _ rows: PostgresRowSequence
    ) async throws -> MessageState? {
        for try await row in rows {
            let value = try row.decode(
                (Int64, Int64).self
            )

            return MessageState(
                id: value.0,
                threadID: value.1
            )
        }

        return nil
    }

    private func firstMessageUpsert(
        _ rows: PostgresRowSequence
    ) async throws -> (
        Int64,
        Int64?
    )? {
        for try await row in rows {
            return try row.decode(
                (Int64, Int64?).self
            )
        }

        return nil
    }

    private func firstInt64(
        _ rows: PostgresRowSequence
    ) async throws -> Int64? {
        for try await row in rows {
            return try row.decode(
                Int64.self
            )
        }

        return nil
    }
}
