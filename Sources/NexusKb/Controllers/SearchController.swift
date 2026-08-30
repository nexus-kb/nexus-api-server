import Vapor

struct SearchController {
    func index(
        _ req: Request
    ) async throws -> MailSearchCollectionView {
        let parameters = try req.query.decode(
            MailSearchQuery.self
        )
        let page = try resolvePage(parameters)
        let result = try await PostgresSearchRepository(
            client: req.postgres
        ).search(
            scope: page.scope,
            offset: page.offset,
            logger: req.logger
        )

        return MailSearchCollectionView(result)
    }

    private func resolvePage(
        _ query: MailSearchQuery
    ) throws -> (
        scope: MailSearchScope,
        offset: Int
    ) {
        guard let encodedCursor = query.cursor else {
            let limit = query.limit ?? 25
            try validate(limit: limit)

            guard let filter = try resolveFilter(
                query.q
            ) else {
                throw Abort(
                    .badRequest,
                    reason:
                        "q must contain text or a search filter"
                )
            }

            return (
                MailSearchScope(
                    limit: limit,
                    mailingList: query.mailingList,
                    filter: filter
                ),
                0
            )
        }

        let cursor: MailSearchCursor

        do {
            cursor = try PaginationCursorCodec
                .decodeMailSearch(encodedCursor)
        } catch {
            throw Abort(
                .badRequest,
                reason: "Invalid pagination cursor"
            )
        }

        try validate(limit: cursor.scope.limit)
        let requestedFilter: MailSearchFilter?

        if let requestedQuery = query.q {
            requestedFilter = try resolveFilter(
                requestedQuery
            )
        } else {
            requestedFilter = nil
        }

        guard query.limit == nil
                || query.limit == cursor.scope.limit,
              query.mailingList == nil
                || query.mailingList
                    == cursor.scope.mailingList,
              query.q == nil
                || requestedFilter == cursor.scope.filter
        else {
            throw Abort(
                .badRequest,
                reason:
                    "Pagination cursor does not match the requested filters"
            )
        }

        return (cursor.scope, cursor.offset)
    }

    private func resolveFilter(
        _ query: String?
    ) throws -> MailSearchFilter? {
        do {
            return try MailSearchParser.parse(query)
        } catch let error as MailSearchParseError {
            throw Abort(
                .badRequest,
                reason: error.description
            )
        }
    }

    private func validate(limit: Int) throws {
        guard (1...100).contains(limit) else {
            throw Abort(
                .badRequest,
                reason:
                    "limit must be between 1 and 100"
            )
        }
    }
}
