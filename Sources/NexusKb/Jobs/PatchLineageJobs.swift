import Foundation
import PostgresNIO
import Queues
import Vapor

enum PatchLineageJobError:
    Error,
    Sendable,
    Equatable
{
    case invalidBatchSize(Int)
}

struct RebuildPatchLineagesJob: AsyncJob {
    struct Cursor:
        Codable,
        Sendable,
        Equatable
    {
        let sentAt: Date?
        let patchSetID: Int64
    }

    struct Payload:
        Codable,
        Sendable
    {
        private enum CodingKeys:
            String,
            CodingKey
        {
            case batchSize
            case targetPatchSetID
            case cursor
        }

        let batchSize: Int
        let targetPatchSetID: Int64?
        let cursor: Cursor?

        init(
            batchSize: Int,
            targetPatchSetID: Int64? = nil,
            cursor: Cursor? = nil
        ) {
            self.batchSize = batchSize
            self.targetPatchSetID =
                targetPatchSetID
            self.cursor = cursor
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(
                keyedBy: CodingKeys.self
            )

            batchSize = try values.decode(
                Int.self,
                forKey: .batchSize
            )
            targetPatchSetID =
                try values.decodeIfPresent(
                    Int64.self,
                    forKey: .targetPatchSetID
                )
            cursor = try values.decodeIfPresent(
                Cursor.self,
                forKey: .cursor
            )
        }

        func successor(
            targetPatchSetID: Int64,
            cursor: Cursor
        ) -> Self {
            Self(
                batchSize: batchSize,
                targetPatchSetID:
                    targetPatchSetID,
                cursor: cursor
            )
        }
    }

    private struct PendingPatchSet {
        let id: Int64
        let sentAt: Date?
    }

    static let batchSizeRange = 1...1_000

    func dequeue(
        _ context: QueueContext,
        _ payload: Payload
    ) async throws {
        guard Self.batchSizeRange.contains(
            payload.batchSize
        ) else {
            throw PatchLineageJobError
                .invalidBatchSize(
                    payload.batchSize
                )
        }

        let resolvedTargetPatchSetID: Int64?

        if let target = payload.targetPatchSetID {
            resolvedTargetPatchSetID = target
        } else {
            resolvedTargetPatchSetID =
                try await targetPatchSetID(
                    context: context
                )
        }

        guard let targetPatchSetID =
                resolvedTargetPatchSetID
        else {
            return
        }

        let patchSets = try await pendingPatchSets(
            limit: payload.batchSize,
            targetPatchSetID: targetPatchSetID,
            cursor: payload.cursor,
            context: context
        )

        guard !patchSets.isEmpty else {
            return
        }

        let skippedPatchSetIDs =
            try await context.application
            .postgres
            .withTransaction(
                logger: context.logger
            ) { connection in
                var skippedPatchSetIDs: [Int64] = []

                for patchSet in patchSets {
                    do {
                        try await PostgresPatchLineageService()
                            .reconcile(
                                patchSetID: patchSet.id,
                                connection: connection,
                                logger: context.logger
                            )
                    } catch PostgresPatchLineageError
                        .missingPatchSet(let patchSetID)
                    {
                        skippedPatchSetIDs.append(
                            patchSetID
                        )
                    }
                }

                return skippedPatchSetIDs
            }

        if !skippedPatchSetIDs.isEmpty {
            context.logger.warning(
                "Skipped patchsets without lineage source messages",
                metadata: [
                    "count":
                        "\(skippedPatchSetIDs.count)",
                    "first-patchset-id":
                        "\(skippedPatchSetIDs.first ?? 0)",
                    "last-patchset-id":
                        "\(skippedPatchSetIDs.last ?? 0)",
                ]
            )
        }

        if patchSets.count == payload.batchSize,
           let last = patchSets.last
        {
            try await context.queue.dispatch(
                Self.self,
                payload.successor(
                    targetPatchSetID:
                        targetPatchSetID,
                    cursor: Cursor(
                        sentAt: last.sentAt,
                        patchSetID: last.id
                    )
                ),
                maxRetryCount: 3
            )
        }
    }

    private func targetPatchSetID(
        context: QueueContext
    ) async throws -> Int64? {
        let rows = try await context.application
            .postgres
            .query(
                """
                SELECT max(id)
                FROM patchsets
                """,
                logger: context.logger
            )

        for try await row in rows {
            return try row.decode(Int64?.self)
        }

        return nil
    }

    private func pendingPatchSets(
        limit: Int,
        targetPatchSetID: Int64,
        cursor: Cursor?,
        context: QueueContext
    ) async throws -> [PendingPatchSet] {
        let rows: PostgresRowSequence

        if let cursor,
           let sentAt = cursor.sentAt
        {
            rows = try await context.application
                .postgres
                .query(
                    """
                    SELECT
                        patchset.id,
                        patchset.sent_at
                    FROM patchsets AS patchset
                    WHERE patchset.id <=
                            \(targetPatchSetID)
                      AND patchset.sent_at IS NOT NULL
                      AND (
                            patchset.sent_at,
                            patchset.id
                          ) > (
                            \(sentAt),
                            \(cursor.patchSetID)
                          )
                      AND NOT EXISTS (
                            SELECT 1
                            FROM patchset_lineage_state AS state
                            WHERE state.patchset_id =
                                    patchset.id
                              AND (
                                    state.manual_lock
                                    OR state.matcher_version >=
                                        \(PostgresPatchLineageService.matcherVersion)
                                  )
                          )
                    ORDER BY
                        patchset.sent_at ASC NULLS FIRST,
                        patchset.id ASC
                    LIMIT \(limit)
                    """,
                    logger: context.logger
                )
        } else {
            let afterNullPatchSetID =
                cursor?.patchSetID ?? 0

            rows = try await context.application
                .postgres
                .query(
                    """
                    SELECT
                        patchset.id,
                        patchset.sent_at
                    FROM patchsets AS patchset
                    WHERE patchset.id <=
                            \(targetPatchSetID)
                      AND (
                            patchset.sent_at IS NOT NULL
                            OR patchset.id >
                                \(afterNullPatchSetID)
                          )
                      AND NOT EXISTS (
                            SELECT 1
                            FROM patchset_lineage_state AS state
                            WHERE state.patchset_id =
                                    patchset.id
                              AND (
                                    state.manual_lock
                                    OR state.matcher_version >=
                                        \(PostgresPatchLineageService.matcherVersion)
                                  )
                          )
                    ORDER BY
                        patchset.sent_at ASC NULLS FIRST,
                        patchset.id ASC
                    LIMIT \(limit)
                    """,
                    logger: context.logger
                )
        }

        var values: [PendingPatchSet] = []

        for try await row in rows {
            let cells = Array(row)

            values.append(
                PendingPatchSet(
                    id: try cells[0]
                        .decode(Int64.self),
                    sentAt: try cells[1]
                        .decode(Date?.self)
                )
            )
        }

        return values
    }
}
