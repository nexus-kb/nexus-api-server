@testable import NexusKb
import Vapor
import VaporTesting
import Testing

@Suite("Read API routing tests")
struct ReadAPIRoutingTests {
    @Test(
        "Encoded Message-ID remains one path component"
    )
    func encodedMessageIDPath() async throws {
        let messageID =
            "message/path?query#fragment%value@example.com"
        let encoded = try #require(
            messageID.addingPercentEncoding(
                withAllowedCharacters:
                    .messageIDPathAllowed
            )
        )

        try await withApp { app in
            app.get(
                "echo",
                ":messageID"
            ) { req async throws -> String in
                try req.messageIdentifier(
                    parameter: "messageID"
                ).value
            }

            try await app.testing().test(
                .GET,
                "/echo/\(encoded)"
            ) { response async in
                #expect(response.status == .ok)
                #expect(response.body.string == messageID)
            }
        }
    }
}

private extension CharacterSet {
    static var messageIDPathAllowed: CharacterSet {
        var value = CharacterSet.urlPathAllowed
        value.remove(charactersIn: "/?#%")
        return value
    }
}
