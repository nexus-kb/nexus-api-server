//
//  PostgresQueuesDriver.swift
//  NexusKb
//
//  Created by Tanuj Ravi Rao on 8/12/26.
//

import Foundation
import PostgresNIO
import Queues

struct PostgresQueuesDriver:
    QueuesDriver
{
    let client: PostgresClient
    let leaseOwner: UUID

    func makeQueue(
        with context: QueueContext
    ) -> any Queue {
        PostgresQueue(
            client: client,
            context: context,
            leaseOwner: leaseOwner
        )
    }

    func shutdown() {}
}

private enum PostgresQueueError: Error {
    case missingJob(String)
}

private struct PostgresQueue: AsyncQueue {
    let client: PostgresClient
    let context: QueueContext
    let leaseOwner: UUID
    
    private var visibilityTimeoutSeconds: Int {
        PublicInboxIngestConfiguration
            .queueVisibilityTimeoutSeconds
    }
    
    private var queueKey: String {
        context.queueName.makeKey(with: context.configuration.persistenceKey)
    }
    
    private func execute(
        _ query: PostgresQuery
    ) async throws {
        let rows = try await client.query(
            query,
            logger: context.logger
        )

        for try await _ in rows {}
    }
    
    func get(_ id: JobIdentifier) async throws -> JobData {
        let rows = try await client.query(
            """
            SELECT
                payload,
                max_retry_count,
                attempts,
                delay_until,
                queued_at,
                job_name
            FROM vapor_queue_jobs
            WHERE id = \(id.string)
                AND queue_key = \(queueKey)
                AND state = 'processing'
                AND lease_owner = \(leaseOwner)
            """,
            logger: context.logger
        )
        
        for try await row in rows {
            let (
                payload,
                maxRetryCount,
                attempts,
                delayUntil,
                queuedAt,
                jobName
            ) = try row.decode(
                (
                    Data,
                    Int,
                    Int,
                    Date?,
                    Date,
                    String
                ).self
            )

            return JobData(
                payload: [UInt8](payload),
                maxRetryCount: maxRetryCount,
                jobName: jobName,
                delayUntil: delayUntil,
                queuedAt: queuedAt,
                attempts: attempts
            )
        }
        
        throw PostgresQueueError.missingJob(id.string)
    }
    
    func set(
        _ id: JobIdentifier,
        to data: JobData
    ) async throws {
        try await execute(
            """
            INSERT INTO vapor_queue_jobs (
                id,
                queue_key,
                job_name,
                payload,
                max_retry_count,
                attempts,
                delay_until,
                queued_at,
                state,
                lease_owner,
                lease_expires_at,
                updated_at
            )
            VALUES (
                \(id.string),
                \(queueKey),
                \(data.jobName),
                \(Data(data.payload)),
                \(data.maxRetryCount),
                \(data.attempts ?? 0),
                \(data.delayUntil),
                \(data.queuedAt),
                'stored',
                NULL,
                NULL,
                now()
            )
            ON CONFLICT (id) DO UPDATE
            SET
                queue_key = EXCLUDED.queue_key,
                job_name = EXCLUDED.job_name,
                payload = EXCLUDED.payload,
                max_retry_count = EXCLUDED.max_retry_count,
                attempts = EXCLUDED.attempts,
                delay_until = EXCLUDED.delay_until,
                queued_at = EXCLUDED.queued_at,
                state = 'stored',
                lease_owner = NULL,
                lease_expires_at = NULL,
                updated_at = now()
            """
        )
    }
    
    func clear(
        _ id: JobIdentifier
    ) async throws {
        let rows = try await client.query(
            """
            DELETE FROM vapor_queue_jobs
            WHERE id = \(id.string)
              AND queue_key = \(queueKey)
              AND (
                  state <> 'processing'
                  OR lease_owner = \(leaseOwner)
              )
            RETURNING id
            """,
            logger: context.logger
        )

        for try await _ in rows {
            return
        }

        throw PostgresQueueLeaseError.lost(
            id.string
        )
    }
    
    func push(_ id: JobIdentifier) async throws {
        try await execute(
            """
            UPDATE vapor_queue_jobs
            SET
                state = 'ready',
                lease_owner = NULL,
                lease_expires_at = NULL,
                updated_at = now()
            WHERE id = \(id.string)
              AND queue_key = \(queueKey)
              AND (
                  state = 'stored'
                  OR (
                      state = 'processing'
                      AND lease_owner = \(leaseOwner)
                  )
              )
            """
        )
    }
    
    func pop() async throws -> JobIdentifier? {
        let rows = try await client.query(
            """
            WITH candidate AS (
                SELECT id
                FROM vapor_queue_jobs
                WHERE queue_key = \(queueKey)
                  AND (
                      state = 'ready'
                      OR (
                          state = 'processing'
                          AND lease_expires_at <= now()
                      )
                      OR (
                          state = 'stored'
                          AND updated_at < now() - interval '30 seconds'
                      )
                  )
                  AND (
                      delay_until IS NULL
                      OR delay_until < now()
                  )
                ORDER BY queued_at, id
                FOR UPDATE SKIP LOCKED
                LIMIT 1
            )
            UPDATE vapor_queue_jobs AS job
            SET
                state = 'processing',
                lease_owner = \(leaseOwner),
                lease_expires_at =
                    now() + make_interval(
                        secs => \(visibilityTimeoutSeconds)::double precision
                    ),
                updated_at = now()
            FROM candidate
            WHERE job.id = candidate.id
            RETURNING job.id
            """,
            logger: context.logger
        )

        for try await row in rows {
            let id = try row.decode(String.self)
            return JobIdentifier(string: id)
        }

        return nil
    }
}
