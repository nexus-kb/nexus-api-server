import Vapor

struct ThreadController {
    func index(
        _ req: Request
    ) async throws -> ThreadListView {
        let query = try req.query.decode(
            ThreadListQuery.self
        )

        let page = try resolvePage(query)
        let result = try await PostgresReadRepository(
            client: req.postgres
        ).threads(
            scope: page.scope,
            cursor: page.cursor,
            logger: req.logger
        )

        return ThreadListView(result)
    }

    func show(
        _ req: Request
    ) async throws -> ThreadDetailView {
        let rootMessageID = try req.messageIdentifier(
            parameter: "rootMessageID"
        )

        guard let value = try await PostgresReadRepository(
            client: req.postgres
        ).thread(
            rootMessageID: rootMessageID,
            logger: req.logger
        ) else {
            throw Abort(
                .notFound,
                reason: "Thread not found"
            )
        }

        return ThreadDetailView(value)
    }

    func messages(
        _ req: Request
    ) async throws -> ThreadMessagesView {
        let rootMessageID = try req.messageIdentifier(
            parameter: "rootMessageID"
        )
        let query = try req.query.decode(
            MessageListQuery.self
        )
        let page = try resolveMessagePage(
            query,
            rootMessageID: rootMessageID
        )

        guard let value = try await PostgresReadRepository(
            client: req.postgres
        ).messages(
            rootMessageID: rootMessageID,
            limit: page.limit,
            cursor: page.cursor,
            logger: req.logger
        ) else {
            throw Abort(
                .notFound,
                reason: "Thread not found"
            )
        }

        return ThreadMessagesView(value)
    }

    private func resolvePage(
        _ query: ThreadListQuery
    ) throws -> (
        scope: ThreadPageScope,
        cursor: ThreadCursor?
    ) {
        guard let encodedCursor = query.cursor else {
            let limit = query.limit ?? 25
            try validate(
                limit: limit,
                maximum: 100
            )

            return (
                ThreadPageScope(
                    limit: limit,
                    mailingList: query.mailingList,
                    subsystem: query.subsystem,
                    kind: query.kind
                ),
                nil
            )
        }

        let cursor: ThreadCursor

        do {
            cursor = try PaginationCursorCodec
                .decodeThread(encodedCursor)
        } catch {
            throw Abort(
                .badRequest,
                reason: "Invalid pagination cursor"
            )
        }

        try validate(
            limit: cursor.scope.limit,
            maximum: 100
        )

        guard query.limit == nil
                || query.limit == cursor.scope.limit,
              query.mailingList == nil
                || query.mailingList
                    == cursor.scope.mailingList,
              query.subsystem == nil
                || query.subsystem
                    == cursor.scope.subsystem,
              query.kind == nil
                || query.kind == cursor.scope.kind
        else {
            throw Abort(
                .badRequest,
                reason:
                    "Pagination cursor does not match the requested filters"
            )
        }

        return (cursor.scope, cursor)
    }

    private func resolveMessagePage(
        _ query: MessageListQuery,
        rootMessageID: MessageIdentifier
    ) throws -> (
        limit: Int,
        cursor: MessageCursor?
    ) {
        guard let encodedCursor = query.cursor else {
            let limit = query.limit ?? 100
            try validate(
                limit: limit,
                maximum: 200
            )
            return (limit, nil)
        }

        let cursor: MessageCursor

        do {
            cursor = try PaginationCursorCodec
                .decodeMessage(encodedCursor)
        } catch {
            throw Abort(
                .badRequest,
                reason: "Invalid pagination cursor"
            )
        }

        try validate(
            limit: cursor.limit,
            maximum: 200
        )

        guard cursor.rootMessageID
                == rootMessageID.value,
              query.limit == nil
                || query.limit == cursor.limit
        else {
            throw Abort(
                .badRequest,
                reason:
                    "Pagination cursor does not match the requested thread"
            )
        }

        return (cursor.limit, cursor)
    }

    private func validate(
        limit: Int,
        maximum: Int
    ) throws {
        guard (1...maximum).contains(limit) else {
            throw Abort(
                .badRequest,
                reason:
                    "limit must be between 1 and \(maximum)"
            )
        }
    }
}
