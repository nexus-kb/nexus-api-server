import Vapor
import Queues

private struct StartPublicInboxIngestRequest:
    Content
{
    let mailingListID: Int64
    let epoch: Int32?
    let batchSize: Int?
    let runMessageLimitPerEpoch: Int?
    let scanAll: Bool?
}

func routes(_ app: Application) throws {
    app.get { req async throws -> Response in
        try await req.fileio.asyncStreamFile(
            at:
                req.application.directory
                    .publicDirectory
                + "index.html"
        )
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    app.post("jobs", "hello") { req async throws -> HTTPStatus in
        try await req.queue.dispatch(
            HelloJob.self,
            .init()
        )

        return .accepted
    }

    app.post(
        "jobs",
        "public-inbox",
        "ingest"
    ) { req async throws -> HTTPStatus in
        let input = try req.content.decode(
            StartPublicInboxIngestRequest.self
        )

        let batchSize =
            input.batchSize
            ?? PublicInboxIngestConfiguration
            .defaultBatchSize

        guard
            PublicInboxIngestConfiguration
                .batchSizeRange
                .contains(batchSize)
                else {
            throw Abort(
                .badRequest,
                reason:
                    "batchSize must be between 1 and 10000"
            )
        }

        if let epoch = input.epoch,
           epoch < 0
            {
            throw Abort(
                .badRequest,
                reason:
                    "epoch must be non-negative"
            )
        }

        let runMessageLimitPerEpoch =
        input.scanAll == true
        ? nil
        : input.runMessageLimitPerEpoch
                ?? 20000

        if let limit =
            runMessageLimitPerEpoch,
           limit < 1
            {
            throw Abort(
                .badRequest,
                reason:
                    "runMessageLimitPerEpoch must be positive"
            )
        }

        try await req.queue.dispatch(
            ScanPublicInboxArchiveJob.self,
            .init(
                mailingListID:
                    input.mailingListID,
                epoch: input.epoch,
                batchSize: batchSize,
                runMessageLimitPerEpoch:
                    runMessageLimitPerEpoch
            )
        )

        return .accepted
    }

    let api = app.grouped(
        "api",
        "v1"
    )
    let threadController =
        ThreadController()
    let messageController =
        MessageController()
    let referenceDataController =
        ReferenceDataController()

    api.get(
        "threads",
        use: threadController.index
    )

    api.get(
        "threads",
        ":rootMessageID",
        "messages",
        use: threadController.messages
    )

    api.get(
        "threads",
        ":rootMessageID",
        use: threadController.show
    )

    api.get(
        "messages",
        ":messageID",
        use: messageController.show
    )

    api.get(
        "mailing-lists",
        use: referenceDataController
            .mailingLists
    )

    api.get(
        "subsystems",
        use: referenceDataController
            .subsystems
    )
}
