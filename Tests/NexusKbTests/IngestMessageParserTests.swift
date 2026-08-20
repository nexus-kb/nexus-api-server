import Foundation
import Testing
@testable import NexusKb

@Test
func requiresMessageIDOnlyAtNexusBoundary() {
    let raw = Data(
        """
        From: person@example.com
        Subject: Message without an identifier

        Body
        """.utf8
    )

    #expect(
        throws: IngestMessageParserError
            .missingMessageID
    ) {
        try IngestMessageParser().parse(raw)
    }
}

@Test
func reportsMessagesWithoutHeadersAsUnparseable() {
    #expect(
        throws: IngestMessageParserError
            .unparseableMessage
    ) {
        try IngestMessageParser().parse(Data())
    }
}

@Test
func canonicalizesLegacyThreadIdentifiersForIngest() throws {
    let raw = Data(
        """
        From: Mark Richards <m.richards@utoronto.ca>
        Message-ID: <200203040330.g243URr05337@3 (NXDOMAIN) >
        In-Reply-To: <parent@example.com (legacy comment)>
        References: <root @example.com> <parent@example.com (legacy comment)>
        Subject: Re: Invalid @home email addresses

        Body
        """.utf8
    )

    let parsed = try IngestMessageParser().parse(raw)

    #expect(
        parsed.message.messageID
            == "200203040330.g243URr05337@3"
    )
    #expect(
        parsed.message.inReplyTo
            == "parent@example.com"
    )
    #expect(
        parsed.message.references == [
            "root@example.com",
            "parent@example.com",
        ]
    )
}

@Test
func selectsTheLastUsableMessageIDAcrossListsAndRepeatedHeaders() throws {
    let raw = Data(
        """
        Message-ID: <> <first @example.com> <second@example.com>
        Message-ID: <last@example.com>

        Body
        """.utf8
    )

    let parsed = try IngestMessageParser().parse(raw)

    #expect(parsed.message.messageID == "last@example.com")
    #expect(
        parsed.messageIDAliases == [
            "first@example.com",
            "second@example.com",
        ]
    )
}

@Test
func projectsRepeatedAndGroupedConcreteRecipients() throws {
    let raw = Data(
        """
        From: A Display Name Without An Address
        From: Sender <sender@example.com>
        To: First <first@example.com>, Missing Address
        To: Kernel Group: Second <second@example.com>, third@example.com;
        Cc: Undisclosed:;
        Cc: Fourth <fourth@example.com>
        Message-ID: <address-projection@example.com>
        Subject: Address projection

        Body
        """.utf8
    )

    let parsed = try IngestMessageParser().parse(raw)

    #expect(
        parsed.message.from
            == IngestMailbox(
                name: "Sender",
                address: "sender@example.com"
            )
    )
    #expect(
        parsed.message.to.map(\.address) == [
            "first@example.com",
            "second@example.com",
            "third@example.com",
        ]
    )
    #expect(
        parsed.message.cc.map(\.address)
            == ["fourth@example.com"]
    )
}

@Test
func resolvesB4AliasFromOriginalSender() throws {
    let raw = Data(
        """
        From: devnull+real.example.com@kernel.org
        X-Original-From: Real Person <real@example.com>
        Message-ID: <b4-alias@example.com>
        Subject: Alias

        Body
        """.utf8
    )

    let parsed = try IngestMessageParser().parse(raw)

    #expect(
        parsed.author
            == IngestMailbox(
                name: "Real Person",
                address: "real@example.com"
            )
    )
}

@Test
func appliesNexusProjectionFallbacks() throws {
    let raw = Data(
        """
        Message-ID: <fallbacks@example.com>

        Body
        """.utf8
    )

    let parsed = try IngestMessageParser().parse(raw)

    #expect(parsed.message.subject == "(no subject)")
    #expect(
        parsed.author
            == IngestMailbox(
                name: nil,
                address: "unknown@localhost"
            )
    )
    #expect(parsed.message.textBody == "Body")
    #expect(ParsedPatchMetadata.parserVersion == 3)
}

@Test
func projectsTimezoneAwareDateAsAbsoluteDate() throws {
    let raw = Data(
        """
        Message-ID: <date@example.com>
        Date: Tue, 18 Aug 2026 12:00:00 -0400

        Body
        """.utf8
    )

    let parsed = try IngestMessageParser().parse(raw)
    let expected = Date(
        timeIntervalSince1970: 1_787_068_800
    )

    #expect(parsed.message.date == expected)
}
