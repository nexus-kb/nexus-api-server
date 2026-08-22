@testable import NexusKb
import VaporTesting
import Testing

@Suite("App Tests")
struct NexusKbTests {
    @Test("Legacy job routes are removed")
    func legacyJobRoutesAreRemoved() async throws {
        try await withApp(configure: configure) { app in
            try await app.testing().test(.POST, "/jobs/hello", afterResponse: { res async in
                #expect(res.status == .notFound)
            })
        }
    }
}
