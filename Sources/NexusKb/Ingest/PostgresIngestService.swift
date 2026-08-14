//
//  PostgresIngestService.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/13/26.
//

import Foundation
import PostgresNIO
import Vapor
import MailParser

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

struct PostgresIngestService: Sendable {
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

    func ingest(
        commit: PublicInboxCommit,
        parsed: ParsedIngestMessage,
        mailingListID: Int64,
        epoch: Int32,
        expectedPreviousCommitOID: String?,
        logger: Logger
    ) async throws -> PostgresIngestResult {
        let normalized = PostgresTextNormalizer.normalize(parsed)
        return try await client.withTransaction(
            logger: logger
        ) { connection in
            try await ensureEpoch(
                mailingListID: mailingListID,
                epoch: epoch,
                connection: connection,
                logger: logger
            )

            let currentCursor = try await lockedCursor(
                mailingListID: mailingListID,
                epoch: epoch,
                connection: connection,
                logger: logger
            )

            if currentCursor == commit.commitOID {
                guard let existing = try await existingMessage(
                    messageID: normalized.message.messageID,
                    connection: connection,
                    logger: logger
                ) else {
                    throw PostgresIngestError.missingMessage(
                        normalized.message.messageID
                    )
                }

                return PostgresIngestResult(
                    messageID: existing.id,
                    threadID: existing.threadID,
                    wasAlreadyIngested: true
                )
            }

            guard currentCursor
                    == expectedPreviousCommitOID
            else {
                throw PostgresIngestError.cursorMismatch(
                    expected: expectedPreviousCommitOID,
                    actual: currentCursor
                )
            }

            let persisted = try await persistMessage(
                commit: commit,
                parsed: normalized,
                mailingListID: mailingListID,
                connection: connection,
                logger: logger
            )

            try await advanceCursor(
                mailingListID: mailingListID,
                epoch: epoch,
                expectedPreviousCommitOID:
                    expectedPreviousCommitOID,
                commitOID: commit.commitOID,
                connection: connection,
                logger: logger
            )

            return PostgresIngestResult(
                messageID: persisted.id,
                threadID: persisted.threadID,
                wasAlreadyIngested: false
            )
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
        commit: PublicInboxCommit,
        parsed: ParsedIngestMessage,
        mailingListID: Int64,
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

        let targetThreadID = try await ensureThread(
            for: threadAnchorMessageID,
            timestamp: timestamp,
            connection: connection,
            logger: logger
        )

        if let existing = try await existingMessage(
            messageID: message.messageID,
            connection: connection,
            logger: logger
        ),
        existing.threadID != targetThreadID {
            try await mergeThread(
                existing.threadID,
                into: targetThreadID,
                connection: connection,
                logger: logger
            )
        }

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
            RETURNING id
            """,
            logger: logger
        )

        guard let messageDatabaseID =
                try await firstInt64(rows)
        else {
            throw PostgresIngestError.missingMessage(
                message.messageID
            )
        }

        try await linkMessageToMailingList(
            messageDatabaseID: messageDatabaseID,
            mailingListID: mailingListID,
            blobOID: commit.blobOID,
            connection: connection,
            logger: logger
        )

        try await replaceRecipients(
            messageDatabaseID: messageDatabaseID,
            parsed: parsed,
            connection: connection,
            logger: logger
        )

        try await PostgresPatchIngestService()
            .persist(
                parsed: parsed,
                threadID: targetThreadID,
                timestamp: timestamp,
                connection: connection,
                logger: logger
            )

        try await updateThreadMetadata(
            threadID: targetThreadID,
            rootCandidateMessageID: message.messageID,
            subject: message.subject,
            timestamp: timestamp,
            connection: connection,
            logger: logger
        )

        return (
            messageDatabaseID,
            targetThreadID
        )
    }

    private func ensureThread(
        for messageID: String,
        timestamp: Date,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        if let existing = try await existingMessage(
            messageID: messageID,
            connection: connection,
            logger: logger
        ) {
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
            throw PostgresIngestError.missingThread(
                messageID
            )
        }

        try await execute(
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
            """,
            on: connection,
            logger: logger
        )

        guard let resolved = try await existingMessage(
            messageID: messageID,
            connection: connection,
            logger: logger
        ) else {
            throw PostgresIngestError.missingMessage(
                messageID
            )
        }

        return resolved.threadID
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

    private func linkMessageToMailingList(
        messageDatabaseID: Int64,
        mailingListID: Int64,
        blobOID: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            INSERT INTO messages_mailing_lists (
                message_id,
                mailing_list_id,
                archive_blob_oid
            )
            VALUES (
                \(messageDatabaseID),
                \(mailingListID),
                \(blobOID)
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

    private func replaceRecipients(
        messageDatabaseID: Int64,
        parsed: ParsedIngestMessage,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            DELETE FROM messages_recipients
            WHERE message_id = \(messageDatabaseID)
            """,
            on: connection,
            logger: logger
        )

        let recipients = parsed.message.to.map {
            ($0, RecipientType.to)
        } + parsed.message.cc.map {
            ($0, RecipientType.cc)
        }

        var seen = Set<String>()

        for (
            mailbox,
            recipientType
        ) in recipients {
            let key =
                "\(recipientType.rawValue):"
                + mailbox.address.lowercased()

            guard seen.insert(key).inserted else {
                continue
            }

            let personID = try await ensurePerson(
                name: mailbox.name,
                email: mailbox.address,
                connection: connection,
                logger: logger
            )

            try await execute(
                """
                INSERT INTO messages_recipients (
                    message_id,
                    person_id,
                    recipient_type
                )
                VALUES (
                    \(messageDatabaseID),
                    \(personID),
                    \(recipientType.rawValue)
                )
                ON CONFLICT DO NOTHING
                """,
                on: connection,
                logger: logger
            )
        }
    }

    private func ensurePerson(
        name: String?,
        email: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        let rows = try await connection.query(
            """
            INSERT INTO people (
                name,
                email
            )
            VALUES (
                \(name),
                \(email)
            )
            ON CONFLICT (
                lower(email)
            ) DO UPDATE
            SET name = COALESCE(
                EXCLUDED.name,
                people.name
            )
            RETURNING id
            """,
            logger: logger
        )

        guard let personID =
                try await firstInt64(rows)
        else {
            throw PostgresIngestError.missingMessage(
                email
            )
        }

        return personID
    }

    private func updateThreadMetadata(
        threadID: Int64,
        rootCandidateMessageID: String,
        subject: String,
        timestamp: Date,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            UPDATE threads
            SET
                subject = CASE
                    WHEN root_message_id =
                        \(rootCandidateMessageID)
                    THEN \(subject)
                    ELSE COALESCE(
                        subject,
                        \(subject)
                    )
                END,
                last_updated_at = GREATEST(
                    last_updated_at,
                    \(timestamp)
                )
            WHERE id = \(threadID)
            """,
            on: connection,
            logger: logger
        )
    }

    private func existingMessage(
        messageID: String,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> (
        id: Int64,
        threadID: Int64
    )? {
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

        for try await row in rows {
            return try row.decode(
                (Int64, Int64).self
            )
        }

        return nil
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
