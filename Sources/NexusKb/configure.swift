import Vapor
import Queues

/// configures your application
func configure(_ app: Application) async throws {
    app.middleware.use(
        FileMiddleware(
            publicDirectory:
                app.directory.publicDirectory
        )
    )
    
    // configure postgres
    try await app.configurePostgres()
    
    // configure Vapor Queues using Postgres
    let queueLeaseOwner = UUID()

    app.postgresQueueLeaseOwner =
        queueLeaseOwner

    app.queues.use(
        custom: PostgresQueuesDriver(
            client: app.postgres,
            leaseOwner: queueLeaseOwner
        )
    )
    
    app.queues.configuration.workerCount = 1
    app.queues.add(HelloJob())
    app.queues.add(
        ScanPublicInboxArchiveJob()
    )
    app.queues.add(
        IngestPublicInboxEpochJob()
    )
    app.queues.add(
        RebuildPatchLineagesJob()
    )
    
    // register routes
    try routes(app)
}
