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
    struct Payload:
        Codable,
        Sendable
    {
        let batchSize: Int
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

        let patchSetIDs = try await pendingPatchSetIDs(
            limit: payload.batchSize,
            context: context
        )

        for patchSetID in patchSetIDs {
            _ = try await context.application
                .postgres
                .withTransaction(
                    logger: context.logger
                ) { connection in
                    try await PostgresPatchLineageService()
                        .reconcile(
                            patchSetID: patchSetID,
                            connection: connection,
                            logger: context.logger
                        )
                }
        }

        if patchSetIDs.count == payload.batchSize {
            try await context.queue.dispatch(
                Self.self,
                payload,
                maxRetryCount: 3
            )
        }
    }

    private func pendingPatchSetIDs(
        limit: Int,
        context: QueueContext
    ) async throws -> [Int64] {
        let rows = try await context.application
            .postgres
            .query(
                """
                SELECT patchset.id
                FROM patchsets AS patchset
                LEFT JOIN patchset_lineage_state AS state
                  ON state.patchset_id = patchset.id
                WHERE state.patchset_id IS NULL
                   OR (
                        NOT state.manual_lock
                        AND state.matcher_version <
                            \(PostgresPatchLineageService.matcherVersion)
                   )
                ORDER BY
                    patchset.sent_at ASC NULLS FIRST,
                    patchset.id ASC
                LIMIT \(limit)
                """,
                logger: context.logger
            )
        var values: [Int64] = []

        for try await row in rows {
            values.append(
                try row.decode(Int64.self)
            )
        }

        return values
    }
}
