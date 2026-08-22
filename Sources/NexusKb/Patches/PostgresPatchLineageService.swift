import Foundation
import PostgresNIO
import Vapor

enum PostgresPatchLineageError:
    Error,
    Sendable,
    Equatable
{
    case missingPatchSet(Int64)
    case missingLineage
}

struct PostgresPatchLineageService: Sendable {
    static let matcherVersion: Int32 = 1

    private struct Facts {
        let patchSetID: Int64
        let subject: String
        let authorEmail: String
        let sentAt: Date?
        let primaryMessageID: String
        let inReplyTo: String?
        let metadata: PatchLineageMetadata
    }

    private struct ExistingState {
        let lineageID: Int64
        let source: String
        let manualLock: Bool
    }

    private struct Candidate {
        let lineageID: Int64
        let phase: String
        let revision: Int32
        let revisionExplicit: Bool
        let isResend: Bool
        let sentAt: Date?
    }

    private struct Selection {
        let lineageID: Int64
        let source: String
        let confidence: Int32
    }

    @discardableResult
    func reconcile(
        patchSetID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        let facts = try await loadFacts(
            patchSetID: patchSetID,
            connection: connection,
            logger: logger
        )
        let existing = try await loadExistingState(
            patchSetID: patchSetID,
            connection: connection,
            logger: logger
        )

        if let existing,
           existing.manualLock
        {
            try await upsertState(
                facts: facts,
                selection: Selection(
                    lineageID: existing.lineageID,
                    source: "manual",
                    confidence: 100
                ),
                manualLock: true,
                connection: connection,
                logger: logger
            )
            try await refreshLineage(
                existing.lineageID,
                connection: connection,
                logger: logger
            )
            return existing.lineageID
        }

        let discovered = try await selectLineage(
            for: facts,
            connection: connection,
            logger: logger
        )
        let selection: Selection

        if let discovered {
            selection = discovered
        } else if let existing {
            selection = Selection(
                lineageID: existing.lineageID,
                source: existing.source,
                confidence:
                    confidence(for: existing.source)
            )
        } else {
            selection = Selection(
                lineageID: try await createLineage(
                    facts: facts,
                    connection: connection,
                    logger: logger
                ),
                source: "singleton",
                confidence: 0
            )
        }

        try await upsertState(
            facts: facts,
            selection: selection,
            manualLock: false,
            connection: connection,
            logger: logger
        )

        if existing?.lineageID != selection.lineageID
            || existing?.source != selection.source
        {
            try await insertEvent(
                patchSetID: patchSetID,
                previousLineageID:
                    existing?.lineageID,
                selection: selection,
                connection: connection,
                logger: logger
            )
        }

        try await refreshLineage(
            selection.lineageID,
            connection: connection,
            logger: logger
        )

        if let oldLineageID = existing?.lineageID,
           oldLineageID != selection.lineageID
        {
            try await refreshLineage(
                oldLineageID,
                connection: connection,
                logger: logger
            )
            try await deleteEmptyLineage(
                oldLineageID,
                connection: connection,
                logger: logger
            )
        }

        return selection.lineageID
    }

    private func loadFacts(
        patchSetID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Facts {
        let rows = try await connection.query(
            """
            SELECT
                patchset.subject,
                patchset.author,
                patchset.sent_at,
                COALESCE(
                    cover_message.message_id,
                    first_patch_message.message_id
                ),
                COALESCE(
                    cover_message.body,
                    first_patch_message.body,
                    ''
                ),
                COALESCE(
                    cover_message.in_reply_to,
                    first_patch_message.in_reply_to
                )
            FROM patchsets AS patchset
            LEFT JOIN messages AS cover_message
              ON cover_message.message_id =
                    patchset.cover_letter_message_id
            LEFT JOIN LATERAL (
                SELECT message.*
                FROM patches AS patch
                JOIN messages AS message
                  ON message.message_id =
                        patch.message_id
                WHERE patch.patchset_id =
                        patchset.id
                ORDER BY patch.part_index, patch.id
                LIMIT 1
            ) AS first_patch_message ON true
            WHERE patchset.id = \(patchSetID)
            FOR UPDATE OF patchset
            """,
            logger: logger
        )

        for try await row in rows {
            let cells = Array(row)
            let subject = try cells[0]
                .decode(String?.self) ?? "(no subject)"
            let author = try cells[1]
                .decode(String?.self) ?? "unknown@localhost"
            let sentAt = try cells[2]
                .decode(Date?.self)
            guard let messageID = try cells[3]
                .decode(String?.self)
            else {
                throw PostgresPatchLineageError
                    .missingPatchSet(patchSetID)
            }
            let body = try cells[4]
                .decode(String.self)
            let inReplyTo = try cells[5]
                .decode(String?.self)
            let authorEmail =
                IngestAddressProjector
                .parseList(author)
                .first?.address
                ?? author

            return Facts(
                patchSetID: patchSetID,
                subject: subject,
                authorEmail: authorEmail,
                sentAt: sentAt,
                primaryMessageID: messageID,
                inReplyTo: inReplyTo,
                metadata:
                    PatchLineageMetadataParser
                    .parse(
                        subject: subject,
                        body: body
                    )
            )
        }

        throw PostgresPatchLineageError
            .missingPatchSet(patchSetID)
    }

    private func loadExistingState(
        patchSetID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> ExistingState? {
        let rows = try await connection.query(
            """
            SELECT
                lineage_id,
                match_source,
                manual_lock
            FROM patchset_lineage_state
            WHERE patchset_id = \(patchSetID)
            FOR UPDATE
            """,
            logger: logger
        )

        for try await row in rows {
            let value = try row.decode(
                (Int64, String, Bool).self
            )

            return ExistingState(
                lineageID: value.0,
                source: value.1,
                manualLock: value.2
            )
        }

        return nil
    }

    private func selectLineage(
        for facts: Facts,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Selection? {
        if let changeID = facts.metadata.changeID {
            let ids = try await changeIDCandidates(
                changeID: changeID,
                excluding: facts.patchSetID,
                connection: connection,
                logger: logger
            )

            if let lineageID = unique(ids) {
                return Selection(
                    lineageID: lineageID,
                    source: "change-id",
                    confidence: 100
                )
            }
        }

        if let inReplyTo = facts.inReplyTo {
            let ids = try await replyCandidates(
                messageID: inReplyTo,
                excluding: facts.patchSetID,
                connection: connection,
                logger: logger
            )

            if let lineageID = unique(ids) {
                return Selection(
                    lineageID: lineageID,
                    source: "reply-chain",
                    confidence: 98
                )
            }
        }

        let candidates = try await subjectCandidates(
            facts: facts,
            connection: connection,
            logger: logger
        ).filter {
            plausibleRelation(
                facts: facts,
                candidate: $0
            )
        }
        let ids = candidates.map(\.lineageID)

        if let lineageID = unique(ids) {
            return Selection(
                lineageID: lineageID,
                source: "subject-author",
                confidence: 90
            )
        }

        return nil
    }

    private func changeIDCandidates(
        changeID: String,
        excluding patchSetID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> [Int64] {
        let rows = try await connection.query(
            """
            SELECT DISTINCT lineage_id
            FROM patchset_lineage_state
            WHERE patchset_id <> \(patchSetID)
              AND lower(change_id) =
                    lower(\(changeID))
            ORDER BY lineage_id
            """,
            logger: logger
        )

        return try await decodeIDs(rows)
    }

    private func replyCandidates(
        messageID: String,
        excluding patchSetID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> [Int64] {
        let rows = try await connection.query(
            """
            SELECT DISTINCT state.lineage_id
            FROM (
                SELECT patchset.id AS patchset_id
                FROM patchsets AS patchset
                WHERE patchset.cover_letter_message_id =
                        \(messageID)

                UNION

                SELECT patch.patchset_id
                FROM patches AS patch
                WHERE patch.message_id =
                        \(messageID)
            ) AS referenced_patchset
            JOIN patchset_lineage_state AS state
              ON state.patchset_id =
                    referenced_patchset.patchset_id
            WHERE state.patchset_id <>
                    \(patchSetID)
            ORDER BY state.lineage_id
            """,
            logger: logger
        )

        return try await decodeIDs(rows)
    }

    private func subjectCandidates(
        facts: Facts,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> [Candidate] {
        let lowerBound = facts.sentAt?.addingTimeInterval(
            -365 * 86_400
        )
        let upperBound = facts.sentAt?.addingTimeInterval(
            365 * 86_400
        )
        let rows = try await connection.query(
            """
            SELECT DISTINCT ON (state.lineage_id)
                state.lineage_id,
                state.phase,
                state.revision,
                state.revision_explicit,
                state.is_resend,
                patchset.sent_at
            FROM patchset_lineage_state AS state
            JOIN patchsets AS patchset
              ON patchset.id = state.patchset_id
            WHERE state.patchset_id <>
                    \(facts.patchSetID)
              AND state.normalized_subject =
                    \(facts.metadata.normalizedSubject)
              AND lower(state.author_email) =
                    lower(\(facts.authorEmail))
              AND (
                    \(facts.sentAt == nil)
                    OR patchset.sent_at BETWEEN
                        \(lowerBound) AND \(upperBound)
              )
            ORDER BY
                state.lineage_id,
                patchset.sent_at DESC NULLS LAST,
                state.patchset_id DESC
            """,
            logger: logger
        )

        var values: [Candidate] = []

        for try await row in rows {
            let value = try row.decode(
                (
                    Int64,
                    String,
                    Int32,
                    Bool,
                    Bool,
                    Date?
                ).self
            )

            values.append(
                Candidate(
                    lineageID: value.0,
                    phase: value.1,
                    revision: value.2,
                    revisionExplicit: value.3,
                    isResend: value.4,
                    sentAt: value.5
                )
            )
        }

        return values
    }

    private func plausibleRelation(
        facts: Facts,
        candidate: Candidate
    ) -> Bool {
        guard candidate.phase
                == facts.metadata.phase.rawValue
        else {
            return true
        }

        if candidate.revision
            != facts.metadata.revision
        {
            return true
        }

        if candidate.isResend
            || facts.metadata.isResend
        {
            return true
        }

        if !candidate.revisionExplicit,
           !facts.metadata.revisionExplicit,
           candidate.sentAt != facts.sentAt
        {
            return true
        }

        return false
    }

    private func createLineage(
        facts: Facts,
        connection: PostgresConnection,
        logger: Logger
    ) async throws -> Int64 {
        let rows = try await connection.query(
            """
            INSERT INTO patch_lineages (
                canonical_subject,
                first_sent_at,
                latest_sent_at
            )
            VALUES (
                \(facts.metadata.displaySubject),
                \(facts.sentAt),
                \(facts.sentAt)
            )
            RETURNING id
            """,
            logger: logger
        )

        for try await row in rows {
            return try row.decode(Int64.self)
        }

        throw PostgresPatchLineageError
            .missingLineage
    }

    private func upsertState(
        facts: Facts,
        selection: Selection,
        manualLock: Bool,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            INSERT INTO patchset_lineage_state (
                patchset_id,
                lineage_id,
                phase,
                revision,
                revision_explicit,
                is_resend,
                display_subject,
                normalized_subject,
                author_email,
                change_id,
                base_commit,
                match_source,
                match_confidence,
                match_evidence,
                matcher_version,
                manual_lock
            )
            VALUES (
                \(facts.patchSetID),
                \(selection.lineageID),
                \(facts.metadata.phase.rawValue),
                \(facts.metadata.revision),
                \(facts.metadata.revisionExplicit),
                \(facts.metadata.isResend),
                \(facts.metadata.displaySubject),
                \(facts.metadata.normalizedSubject),
                \(facts.authorEmail),
                \(facts.metadata.changeID),
                \(facts.metadata.baseCommit),
                \(selection.source),
                \(selection.confidence),
                jsonb_build_object(
                    'rule', \(selection.source),
                    'primaryMessageId',
                        \(facts.primaryMessageID)
                ),
                \(Self.matcherVersion),
                \(manualLock)
            )
            ON CONFLICT (patchset_id) DO UPDATE
            SET
                lineage_id = EXCLUDED.lineage_id,
                phase = EXCLUDED.phase,
                revision = EXCLUDED.revision,
                revision_explicit =
                    EXCLUDED.revision_explicit,
                is_resend = EXCLUDED.is_resend,
                display_subject =
                    EXCLUDED.display_subject,
                normalized_subject =
                    EXCLUDED.normalized_subject,
                author_email = EXCLUDED.author_email,
                change_id = EXCLUDED.change_id,
                base_commit = EXCLUDED.base_commit,
                match_source = EXCLUDED.match_source,
                match_confidence =
                    EXCLUDED.match_confidence,
                match_evidence =
                    EXCLUDED.match_evidence,
                matcher_version =
                    EXCLUDED.matcher_version,
                manual_lock = EXCLUDED.manual_lock,
                updated_at = now()
            """,
            connection: connection,
            logger: logger
        )
    }

    private func insertEvent(
        patchSetID: Int64,
        previousLineageID: Int64?,
        selection: Selection,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            INSERT INTO patch_lineage_events (
                patchset_id,
                previous_lineage_id,
                lineage_id,
                match_source,
                match_confidence,
                match_evidence,
                matcher_version
            )
            VALUES (
                \(patchSetID),
                \(previousLineageID),
                \(selection.lineageID),
                \(selection.source),
                \(selection.confidence),
                jsonb_build_object(
                    'rule', \(selection.source)
                ),
                \(Self.matcherVersion)
            )
            """,
            connection: connection,
            logger: logger
        )
    }

    private func refreshLineage(
        _ lineageID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            UPDATE patch_lineages AS lineage
            SET
                canonical_subject = summary.display_subject,
                first_sent_at = summary.first_sent_at,
                latest_sent_at = summary.latest_sent_at,
                updated_at = now()
            FROM LATERAL (
                SELECT
                    (
                        SELECT state.display_subject
                        FROM patchset_lineage_state AS state
                        JOIN patchsets AS patchset
                          ON patchset.id = state.patchset_id
                        WHERE state.lineage_id =
                                \(lineageID)
                        ORDER BY
                            (state.phase = 'PATCH') DESC,
                            patchset.sent_at DESC NULLS LAST,
                            state.patchset_id DESC
                        LIMIT 1
                    ) AS display_subject,
                    min(patchset.sent_at) AS first_sent_at,
                    max(patchset.sent_at) AS latest_sent_at
                FROM patchset_lineage_state AS state
                JOIN patchsets AS patchset
                  ON patchset.id = state.patchset_id
                WHERE state.lineage_id = \(lineageID)
            ) AS summary
            WHERE lineage.id = \(lineageID)
              AND summary.display_subject IS NOT NULL
            """,
            connection: connection,
            logger: logger
        )
    }

    private func deleteEmptyLineage(
        _ lineageID: Int64,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        try await execute(
            """
            DELETE FROM patch_lineages AS lineage
            WHERE lineage.id = \(lineageID)
              AND NOT EXISTS (
                    SELECT 1
                    FROM patchset_lineage_state AS state
                    WHERE state.lineage_id = lineage.id
              )
            """,
            connection: connection,
            logger: logger
        )
    }

    private func decodeIDs(
        _ rows: PostgresRowSequence
    ) async throws -> [Int64] {
        var values: [Int64] = []

        for try await row in rows {
            values.append(
                try row.decode(Int64.self)
            )
        }

        return values
    }

    private func unique(
        _ ids: [Int64]
    ) -> Int64? {
        let values = Set(ids)
        return values.count == 1
            ? values.first
            : nil
    }

    private func confidence(
        for source: String
    ) -> Int32 {
        switch source {
        case "manual", "change-id":
            100
        case "reply-chain":
            98
        case "subject-author":
            90
        default:
            0
        }
    }

    private func execute(
        _ query: PostgresQuery,
        connection: PostgresConnection,
        logger: Logger
    ) async throws {
        let rows = try await connection.query(
            query,
            logger: logger
        )

        for try await _ in rows {}
    }
}
