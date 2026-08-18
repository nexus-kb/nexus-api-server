import Foundation
import PostgresNIO
import Vapor

private struct PostgresQueueLeaseOwnerKey:
    StorageKey
{
    typealias Value = UUID
}

extension Application {
    var postgresQueueLeaseOwner: UUID {
        get {
            guard
                let owner =
                    storage[
                        PostgresQueueLeaseOwnerKey.self
                    ]
            else {
                fatalError(
                    "Postgres queue lease owner has not been configured"
                )
            }

            return owner
        }
        set {
            storage[
                PostgresQueueLeaseOwnerKey.self
            ] = newValue
        }
    }
}

enum PostgresQueueLeaseError:
    Error,
    Sendable
{
    case lost(String)
}

actor PostgresQueueJobLease {
    private let client: PostgresClient
    private let jobID: String
    private let ownerID: UUID
    private let logger: Logger

    private var heartbeatTask: Task<Void, Never>?
    private var wasLost = false

    init(
        client: PostgresClient,
        jobID: String,
        ownerID: UUID,
        logger: Logger
    ) {
        self.client = client
        self.jobID = jobID
        self.ownerID = ownerID
        self.logger = logger
    }

    func start() async throws {
        try await renew()

        heartbeatTask = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(
                            PublicInboxIngestConfiguration
                                .queueHeartbeatIntervalSeconds
                        )
                    )

                    try Task.checkCancellation()
                    try await self.renew()
                } catch is CancellationError {
                    return
                } catch {
                    await self.markLost()
                    return
                }
            }
        }
    }

    func assertOwned() async throws {
        guard !wasLost else {
            throw
                PostgresQueueLeaseError
                .lost(jobID)
        }

        try await renew()
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func markLost() {
        wasLost = true
        heartbeatTask = nil
    }

    private func renew() async throws {
        let rows = try await client.query(
            """
            UPDATE vapor_queue_jobs
            SET
                lease_expires_at =
                    now() + make_interval(
                        secs =>
                            \(PublicInboxIngestConfiguration.queueVisibilityTimeoutSeconds)::double precision
                    ),
                updated_at = now()
            WHERE id = \(jobID)
              AND state = 'processing'
              AND lease_owner = \(ownerID)
              AND lease_expires_at > now()
            RETURNING id
            """,
            logger: logger
        )

        for try await _ in rows {
            return
        }

        wasLost = true

        throw
            PostgresQueueLeaseError
            .lost(jobID)
    }
}
