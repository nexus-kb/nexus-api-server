import Foundation
import Queues
import Vapor

private struct StartMaintenanceRequest: Content {
    let mode: MaintenanceMode
}

struct AdminMaintenanceController {
    func startIngest(_ request: Request) async throws -> Response {
        try await startManual(
            request,
            operation: .ingest
        )
    }

    func startPatchLineage(_ request: Request) async throws -> Response {
        try await startManual(
            request,
            operation: .patchLineage
        )
    }

    func grokmirror(_ request: Request) async throws -> Response {
        let repository = PostgresMaintenanceRepository(
            client: request.postgres
        )
        let mailingLists = try await repository.presentMailingLists(
            logger: request.logger
        )
        let run = try await repository.createGrokmirrorRun(
            mailingLists: mailingLists,
            logger: request.logger
        )
        try await dispatch(run: run, request: request)
        return try await accepted(run: run, request: request)
    }

    func show(_ request: Request) async throws -> MaintenanceRunView {
        guard
            let rawID = request.parameters.get("runID"),
            let runID = UUID(uuidString: rawID)
        else {
            throw Abort(.badRequest, reason: "Invalid operation identifier")
        }

        do {
            return try await MaintenanceRunView(
                PostgresMaintenanceRepository(client: request.postgres)
                    .run(id: runID, logger: request.logger)
            )
        } catch MaintenanceRepositoryError.missingRun {
            throw Abort(.notFound, reason: "Operation not found")
        }
    }

    func index(_ request: Request) async throws -> MaintenanceRunListView {
        let limit = request.query[Int.self, at: "limit"] ?? 25
        guard (1...100).contains(limit) else {
            throw Abort(.badRequest, reason: "limit must be between 1 and 100")
        }
        let runs = try await PostgresMaintenanceRepository(
            client: request.postgres
        ).recentRuns(limit: limit, logger: request.logger)
        return MaintenanceRunListView(
            items: runs.map(MaintenanceRunView.init)
        )
    }

    private func startManual(
        _ request: Request,
        operation: MaintenanceStageOperation
    ) async throws -> Response {
        guard let archiveGroup = request.parameters.get("archiveGroup"),
              !archiveGroup.isEmpty
        else {
            throw Abort(.badRequest, reason: "Missing archive group")
        }
        let input = try request.content.decode(StartMaintenanceRequest.self)
        let repository = PostgresMaintenanceRepository(
            client: request.postgres
        )
        guard let mailingList = try await repository.mailingList(
            archiveGroup: archiveGroup,
            logger: request.logger
        ) else {
            throw Abort(.notFound, reason: "Mailing list not found")
        }
        guard let archivePath = mailingList.archivePath,
              !archivePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw Abort(.conflict, reason: "Mailing list has no archive path")
        }

        let run = try await repository.createManualRun(
            mailingList: mailingList,
            operation: operation,
            mode: input.mode,
            logger: request.logger
        )
        try await dispatch(run: run, request: request)
        return try await accepted(run: run, request: request)
    }

    private func dispatch(
        run: MaintenanceRunRecord,
        request: Request
    ) async throws {
        let queueJobID = JobIdentifier()
        do {
            try await request.queue.dispatch(
                MaintenanceWorkflowJob.self,
                .init(
                    runID: run.id,
                    queueJobID: queueJobID.string
                ),
                maxRetryCount: 3,
                id: queueJobID
            )
        } catch {
            try? await PostgresMaintenanceRepository(
                client: request.postgres
            ).markRunFailed(
                run.id,
                error: String(reflecting: error),
                logger: request.logger
            )
            throw error
        }
    }

    private func accepted(
        run: MaintenanceRunRecord,
        request: Request
    ) async throws -> Response {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(
            name: .location,
            value: "/api/v1/admin/operations/\(run.id.uuidString.lowercased())"
        )
        return try await MaintenanceRunView(run).encodeResponse(
            status: .accepted,
            headers: headers,
            for: request
        )
    }
}
