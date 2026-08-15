@testable import NexusKb
import Vapor
import VaporTesting
import Testing

@Suite("Static web routing tests")
struct StaticWebRoutingTests {
    @Test("Root serves the generated SPA and its asset")
    func rootAndAsset() async throws {
        try await withApp { app in
            app.middleware.use(
                FileMiddleware(
                    publicDirectory:
                        app.directory.publicDirectory
                )
            )
            try routes(app)

            var assetPath: String?

            try await app.testing().test(
                .GET,
                "/"
            ) { response async in
                #expect(response.status == .ok)
                #expect(
                    response.headers.contentType
                        == .html
                )
                #expect(
                    response.body.string.contains(
                        "<title>Nexus KB</title>"
                    )
                )

                assetPath = response.body.string
                    .split(separator: "\"")
                    .map(String.init)
                    .first {
                        $0.hasPrefix("/assets/")
                    }
            }

            let path = try #require(assetPath)

            try await app.testing().test(
                .GET,
                path
            ) { response async in
                #expect(response.status == .ok)
                #expect(!response.body.string.isEmpty)
            }
        }
    }
}
