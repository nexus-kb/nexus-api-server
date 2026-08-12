import Vapor
import Queues

func routes(_ app: Application) throws {
    app.get { req async in
        "It works!"
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
}
