import Vapor

struct ReferenceDataController {
    func mailingLists(
        _ req: Request
    ) async throws -> MailingListCollectionView {
        let values = try await PostgresReadRepository(
            client: req.postgres
        ).mailingLists(
            logger: req.logger
        )

        return MailingListCollectionView(
            items: values.map(MailingListView.init)
        )
    }

    func subsystems(
        _ req: Request
    ) async throws -> SubsystemCollectionView {
        let values = try await PostgresReadRepository(
            client: req.postgres
        ).subsystems(
            logger: req.logger
        )

        return SubsystemCollectionView(
            items: values.map(SubsystemView.init)
        )
    }
}
