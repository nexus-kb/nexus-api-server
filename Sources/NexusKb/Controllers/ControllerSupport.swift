import Vapor

extension Request {
    func messageIdentifier(
        parameter: String
    ) throws -> MessageIdentifier {
        guard let rawValue = parameters.get(parameter) else {
            throw Abort(
                .badRequest,
                reason: "Missing Message-ID"
            )
        }

        do {
            return try MessageIdentifier(rawValue)
        } catch {
            throw Abort(
                .badRequest,
                reason: "Invalid Message-ID"
            )
        }
    }
}
