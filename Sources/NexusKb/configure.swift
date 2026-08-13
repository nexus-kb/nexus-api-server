import Vapor
import Queues

/// configures your application
func configure(_ app: Application) async throws {
    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    
    // configure postgres
    try await app.configurePostgres()
    
    // configure Vapor Queues using Postgres
    app.queues.use(
        custom: PostgresQueuesDriver(
            client: app.postgres
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
    
    // register routes
    try routes(app)
}
