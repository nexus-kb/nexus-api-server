import Foundation
import Testing
@testable import MailParser

@Test
func parsesACompleteMessageWithoutRequiringMessageID() throws {
    let raw = Data(
        """
        From: =?UTF-8?Q?Jos=C3=A9_Example?= <jose@example.com>
        To: Kernel Group: One <one@example.com>, two@example.com;
        Subject: =?UTF-8?Q?A_complete_message?=
        Date: Tue, 18 Aug 2026 12:00:00 -0400
        Content-Type: text/plain; charset=utf-8

        Hello, world.
        """.utf8
    )

    let message = try #require(MessageParser().parse(raw))

    #expect(message.messageID == nil)
    #expect(message.subject == "A complete message")
    #expect(message.from?.first?.name == "José Example")
    #expect(message.to?.flattened.map(\.address) == [
        "one@example.com",
        "two@example.com",
    ])
    #expect(message.date?.isNegativeOffset == true)
    #expect(message.date?.offsetHour == 4)
    #expect(message.bodyText(at: 0) == "Hello, world.")
    #expect(message.bodyHTML(at: 0)?.contains("Hello, world.") == true)
    #expect(message.rawMessage == raw)
}

@Test
func decodesAddressWordsOnlyAfterStructuralParsing() throws {
    let raw = Data(
        """
        From: =?UTF-8?Q?Doe=2C_John?= <john@example.com>
        To: =?UTF-8?Q?Ops=3A_=3CTeam=3E?= <ops@example.com>
        Cc: =?UTF-8?Q?=3D=3FUTF-8=3FQ=3FSecond=3F=3D?= <literal@example.com>

        body
        """.utf8
    )
    let message = try #require(MessageParser().parse(raw))

    #expect(message.from?.flattened == [
        MailAddress(name: "Doe, John", address: "john@example.com"),
    ])
    #expect(message.to?.flattened == [
        MailAddress(name: "Ops: <Team>", address: "ops@example.com"),
    ])
    #expect(message.cc?.flattened == [
        MailAddress(
            name: "=?UTF-8?Q?Second?=",
            address: "literal@example.com"
        ),
    ])
}

@Test
func preservesRepeatedAndUnknownHeadersWithLastValueLookup() throws {
    let raw = Data(
        """
        Subject: First
        X-Trace: one
        Subject: Second
        X-Trace: two

        Body
        """.utf8
    )
    let message = try #require(MessageParser().parse(raw))

    #expect(message.subject == "Second")
    #expect(message.headerValues(.subject).map(\.text) == ["First", "Second"])
    #expect(message.header(named: "x-trace")?.text == "two")
    #expect(message.headers.map(\.name) == [
        .subject,
        .other("X-Trace"),
        .subject,
        .other("X-Trace"),
    ])
    #expect(message.rawHeader(.subject) == " Second")
}

@Test
func genericByteCollectionAndHeaderOnlyParsing() throws {
    let bytes = Array("Subject: Header only\r\nMessage-ID: <id@example.com>\r\n".utf8)
    let parser = MessageParser()
    let headers = try #require(parser.parseHeaders(bytes[...]))

    #expect(headers.subject == "Header only")
    #expect(headers.messageID == "id@example.com")
    #expect(headers.parts.count == 1)
    #expect(headers.rootPart?.isEncodingProblem == true)
    #expect(headers.bodyText(at: 0) == nil)
}

@Test
func normalizesSlicedDataForZeroBasedRawOffsets() throws {
    let storage = Data(
        "paddingSubject: Sliced\r\nX-Test: value\r\n\r\nBody".utf8
    )
    let raw: Data = storage.dropFirst(7)
    #expect(raw.startIndex == 7)

    let message = try #require(MessageParser().parse(raw))

    #expect(message.rawMessage.startIndex == 0)
    #expect(message.rawMessage == Data(raw))
    #expect(message.rawHeader(.subject) == " Sliced")
    #expect(message.rawHeader(named: "X-Test") == " value")
}

@Test
func parsesAlternativeRelatedAndAttachments() throws {
    let raw = Data(
        """
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary=outer

        preamble
        --outer
        Content-Type: multipart/alternative; boundary=choice

        --choice
        Content-Type: text/plain; charset=utf-8

        Plain body
        --choice
        Content-Type: text/html; charset=utf-8

        <p>HTML body</p>
        --choice--
        --outer
        Content-Type: application/octet-stream; name=data.bin
        Content-Disposition: attachment; filename=data.bin
        Content-Transfer-Encoding: base64

        AAECAw==
        --outer--
        epilogue
        """.utf8
    )
    let message = try #require(MessageParser().parse(raw))

    #expect(message.textBody.count == 1)
    #expect(message.htmlBody.count == 1)
    #expect(message.bodyText(at: 0) == "Plain body")
    #expect(message.bodyHTML(at: 0) == "<p>HTML body</p>")
    #expect(message.attachments.count == 1)
    #expect(message.attachment(at: 0)?.attachmentName == "data.bin")
    guard case .binary(let data) = message.attachment(at: 0)?.body else {
        Issue.record("Expected decoded binary attachment")
        return
    }
    #expect(data == Data([0, 1, 2, 3]))
}

@Test
func appliesBrokenMultipartFallbacks() throws {
    let noBoundary = try #require(
        MessageParser().parse(
            Data(
                """
                Content-Type: multipart/mixed

                undecodable structure
                """.utf8
            )
        )
    )
    #expect(noBoundary.attachments == [0])
    guard case .binary(let noBoundaryBody) = noBoundary.rootPart?.body else {
        Issue.record("A multipart without a boundary must be binary")
        return
    }
    #expect(String(decoding: noBoundaryBody, as: UTF8.self) == "undecodable structure")

    let missingDelimiter = try #require(
        MessageParser().parse(
            Data(
                """
                Content-Type: multipart/mixed; boundary=missing

                decoded text fallback
                """.utf8
            )
        )
    )
    #expect(missingDelimiter.attachments == [0])
    guard case .text(let missingDelimiterBody) = missingDelimiter.rootPart?.body else {
        Issue.record("A missing declared delimiter must be a text attachment")
        return
    }
    #expect(missingDelimiterBody == "decoded text fallback")
}

@Test
func usesTheFirstDuplicateMIMEParameterLikeMailParser() throws {
    let raw = Data(
        """
        Content-Type: multipart/mixed; boundary=good; boundary=bad

        --good
        Content-Type: text/plain; charset=utf-8; charset=us-ascii

        Parsed child
        --good--
        """.utf8
    )
    let message = try #require(MessageParser().parse(raw))

    #expect(message.rootPart?.contentType?.attribute(named: "boundary") == "good")
    #expect(message.bodyText(at: 0) == "Parsed child")
}

@Test
func trimsLargeFoldedHeaderWhitespaceWithoutChangingTheValue() throws {
    let padding = String(repeating: " \t", count: 16_384)
    let raw = Data(
        ("Keywords:" + padding + "alpha,\r\n\t beta" + padding
            + "\r\n\r\nBody").utf8
    )

    let message = try #require(MessageParser().parse(raw))

    #expect(message.keywords == ["alpha", "beta"])
    #expect(message.bodyText(at: 0) == "Body")
}

@Test
func recoversFailedTransferEncodingAsRawTextAttachment() throws {
    let raw = Data(
        """
        Content-Type: application/octet-stream
        Content-Transfer-Encoding: base64

        this is not base64!
        """.utf8
    )
    let message = try #require(MessageParser().parse(raw))

    #expect(message.rootPart?.isEncodingProblem == true)
    #expect(message.rootPart?.encoding == TransferEncoding.none)
    #expect(message.attachments == [0])
    guard case .text(let text) = message.rootPart?.body else {
        Issue.record("Failed binary transfer should recover as raw text")
        return
    }
    #expect(text == "this is not base64!")
}

@Test
func parsesNestedRFC822GlobalAndDigestMessages() throws {
    let nested = Data(
        """
        Content-Type: multipart/digest; boundary=digest

        --digest

        From: nested@example.com
        Message-ID: <nested@example.com>
        Subject: Nested digest message

        Nested body
        --digest--
        """.utf8
    )
    let digest = try #require(MessageParser().parse(nested))
    let wrapper = try #require(digest.part(at: 1))
    guard case .message(let child) = wrapper.body else {
        Issue.record("multipart/digest child should be a nested message")
        return
    }
    #expect(child.messageID == "nested@example.com")
    #expect(child.bodyText(at: 0) == "Nested body")

    for mediaType in ["message/rfc822", "message/global"] {
        let raw = Data(
            """
            Content-Type: \(mediaType)

            From: child@example.com
            Message-ID: <child@example.com>

            Child body
            """.utf8
        )
        let message = try #require(MessageParser().parse(raw))
        guard case .message(let child) = message.rootPart?.body else {
            Issue.record("\(mediaType) should be a nested message")
            continue
        }
        #expect(child.messageID == "child@example.com")
        #expect(message.rootPart?.decodedLength == child.rootPart?.rawLength)
        #expect((message.rootPart?.decodedLength ?? .max) < message.rawMessage.count)
    }
}

@Test
func limitsRecursivelyDecodedMessageBodiesToThreeLevels() throws {
    var raw = Data("Subject: leaf\n\nbody".utf8)
    for level in 1...4 {
        let encoded = raw.base64EncodedString()
        raw = Data(
            """
            Subject: level \(level)
            Content-Type: message/rfc822
            Content-Transfer-Encoding: base64

            \(encoded)
            """.utf8
        )
    }

    var message = try #require(MessageParser().parse(raw))
    for _ in 0..<3 {
        guard case .message(let nested) = message.rootPart?.body else {
            Issue.record("Expected three decoded nested messages")
            return
        }
        message = nested
    }

    #expect(message.rootPart?.isEncodingProblem == true)
    guard case .binary = message.rootPart?.body else {
        Issue.record("The fourth encoded message must remain binary")
        return
    }
}

@Test
func completeMessageCodableRoundTripsExactly() throws {
    let raw = Data(
        """
        Message-ID: <codable@example.com>
        Content-Type: multipart/mixed; boundary=x

        --x
        Content-Type: text/plain

        Body
        --x
        Content-Type: application/octet-stream
        Content-Transfer-Encoding: base64

        AP+A
        --x--
        """.utf8
    )
    let original = try #require(MessageParser().parse(raw))
    let encoded = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Message.self, from: encoded)

    #expect(decoded == original)
    #expect(decoded.rawMessage == raw)
    #expect(decoded.parts.map(\.offsetHeader) == original.parts.map(\.offsetHeader))
    #expect(decoded.parts.map(\.encoding) == original.parts.map(\.encoding))
}

@Test
func previewUsesUTF8ByteLimits() throws {
    let message = try #require(
        MessageParser().parse(Data("Subject: Preview\n\nAB😀CD".utf8))
    )
    #expect(message.bodyPreview(maxLength: 6) == "AB😀")
    #expect(message.bodyPreview(maxLength: 7) == "AB...")
    #expect(message.bodyPreview(maxLength: 100) == "AB😀CD")
}

@Test
func parserIsSafeForConcurrentReuse() async {
    let parser = MessageParser()
    let raw = Data("Message-ID: <parallel@example.com>\n\nBody".utf8)

    await withTaskGroup(of: Message?.self) { group in
        for _ in 0..<256 {
            group.addTask {
                parser.parse(raw)
            }
        }
        for await message in group {
            #expect(message?.messageID == "parallel@example.com")
            #expect(message?.bodyText(at: 0) == "Body")
        }
    }
}

@Test
func malformedBytesDoNotCrashOrHang() {
    var state: UInt64 = 0x4D_41_49_4C
    let parser = MessageParser()

    for length in 0..<512 {
        var data = Data()
        data.reserveCapacity(length)
        for _ in 0..<length {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            data.append(UInt8(truncatingIfNeeded: state >> 24))
        }
        _ = parser.parse(data)
    }
}
