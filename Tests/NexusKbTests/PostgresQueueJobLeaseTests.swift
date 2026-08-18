@testable import NexusKb
import Foundation
import PostgresNIO
import Testing
import Vapor
import VaporTesting

@Suite(
    "Postgres queue job lease tests",
    .serialized
)
struct PostgresQueueJobLeaseTests {
    @Test("Current owner renews its lease")
    func currentOwnerRenews() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = QueueLeaseFixture(app: app)
            let owner = UUID()

            try await fixture.insert(
                owner: owner,
                expired: false
            )

            let lease = PostgresQueueJobLease(
                client: app.postgres,
                jobID: fixture.jobID,
                ownerID: owner,
                logger: app.logger
            )

            do {
                try await lease.start()
                try await lease.assertOwned()
                await lease.stop()
            } catch {
                await lease.stop()
                try? await fixture.remove()
                throw error
            }

            try await fixture.remove()
        }
    }

    @Test("Different owner cannot renew the lease")
    func rejectsDifferentOwner() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = QueueLeaseFixture(app: app)

            try await fixture.insert(
                owner: UUID(),
                expired: false
            )

            let lease = PostgresQueueJobLease(
                client: app.postgres,
                jobID: fixture.jobID,
                ownerID: UUID(),
                logger: app.logger
            )

            do {
                try await lease.assertOwned()
                Issue.record(
                    "Expected a different owner to lose the lease"
                )
            } catch {
                #expect(error is PostgresQueueLeaseError)
            }

            await lease.stop()
            try await fixture.remove()
        }
    }

    @Test("Expired lease cannot be revived")
    func doesNotReviveExpiredLease() async throws {
        try await withApp(
            configure: configure
        ) { app in
            let fixture = QueueLeaseFixture(app: app)
            let owner = UUID()

            try await fixture.insert(
                owner: owner,
                expired: true
            )

            let lease = PostgresQueueJobLease(
                client: app.postgres,
                jobID: fixture.jobID,
                ownerID: owner,
                logger: app.logger
            )

            do {
                try await lease.assertOwned()
                Issue.record(
                    "Expected an expired lease to remain expired"
                )
            } catch {
                #expect(error is PostgresQueueLeaseError)
            }

            await lease.stop()
            try await fixture.remove()
        }
    }
}

private struct QueueLeaseFixture {
    let app: Application
    let jobID = UUID().uuidString

    func insert(
        owner: UUID,
        expired: Bool
    ) async throws {
        let rows = try await app.postgres.query(
            """
            INSERT INTO vapor_queue_jobs (
                id,
                queue_key,
                job_name,
                payload,
                max_retry_count,
                attempts,
                queued_at,
                state,
                lease_owner,
                lease_expires_at,
                updated_at
            )
            VALUES (
                \(jobID),
                'nexus-kb-lease-test',
                'LeaseTestJob',
                \(Data()),
                0,
                0,
                now(),
                'processing',
                \(owner),
                CASE
                    WHEN \(expired)
                    THEN now() - interval '1 second'
                    ELSE now() + interval '5 minutes'
                END,
                now()
            )
            """,
            logger: app.logger
        )

        for try await _ in rows {}
    }

    func remove() async throws {
        let rows = try await app.postgres.query(
            """
            DELETE FROM vapor_queue_jobs
            WHERE id = \(jobID)
            """,
            logger: app.logger
        )

        for try await _ in rows {}
    }
}
