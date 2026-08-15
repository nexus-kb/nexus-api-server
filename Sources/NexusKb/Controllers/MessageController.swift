import Vapor

struct MessageController {
    func show(
        _ req: Request
    ) async throws -> MessageDetailView {
        let messageID = try req.messageIdentifier(
            parameter: "messageID"
        )

        guard let value = try await PostgresReadRepository(
            client: req.postgres
        ).message(
            messageID: messageID,
            logger: req.logger
        ) else {
            throw Abort(
                .notFound,
                reason: "Message not found"
            )
        }

        return MessageDetailView(value)
    }
}
