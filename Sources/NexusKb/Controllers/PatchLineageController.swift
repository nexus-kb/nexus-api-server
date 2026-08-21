import Vapor

struct PatchLineageController {
    func show(
        _ req: Request
    ) async throws -> PatchLineageDetailView {
        guard let rawID = req.parameters.get(
            "lineageID"
        ),
        let lineageID = Int64(rawID),
        lineageID > 0
        else {
            throw Abort(
                .badRequest,
                reason: "Invalid patch lineage identifier"
            )
        }

        guard let value =
                try await repository(req)
                .lineage(
                    id: lineageID,
                    logger: req.logger
                )
        else {
            throw Abort(
                .notFound,
                reason: "Patch lineage not found"
            )
        }

        return PatchLineageDetailView(value)
    }

    func forThread(
        _ req: Request
    ) async throws -> PatchLineageCollectionView {
        let rootMessageID = try req.messageIdentifier(
            parameter: "rootMessageID"
        )
        let values = try await repository(req)
            .lineages(
                rootMessageID: rootMessageID,
                logger: req.logger
            )

        return PatchLineageCollectionView(values)
    }

    private func repository(
        _ req: Request
    ) -> PostgresPatchLineageReadRepository {
        PostgresPatchLineageReadRepository(
            client: req.postgres
        )
    }
}
